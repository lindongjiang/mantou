//
//  ZXIpaManager.m
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import "ZXIpaManager.h"
#import "NSString+ZXMD5.h"
#import <FMDB/FMDB.h>

@implementation ZXIpaManager

+ (instancetype)sharedManager {
    static ZXIpaManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (BOOL)saveSignedIpa:(ZXIpaModel *)ipaModel {
    NSLog(@"[IpaManager] 保存已签名IPA: %@", ipaModel.title);
    
    if (!ipaModel) {
        NSLog(@"[IpaManager] 错误: IPA模型为空");
        return NO;
    }
    
    // 确保标记为已签名
    ipaModel.isSigned = YES;
    
    // 检查文件是否存在
    if (ipaModel.localPath) {
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:ipaModel.localPath];
        NSLog(@"[IpaManager] 检查文件是否存在: %@, 结果: %@", ipaModel.localPath, fileExists ? @"存在" : @"不存在");
        
        if (!fileExists) {
            NSLog(@"[IpaManager] 警告: 文件不存在于指定路径");
        }
    } else {
        NSLog(@"[IpaManager] 警告: localPath为空");
    }
    
    // 保存到数据库
    BOOL result = [ipaModel zx_dbSave];
    
    if (result) {
        NSLog(@"[IpaManager] 已签名IPA保存成功: %@", ipaModel.title);
        
        // 手动更新数据库中的isSigned标志
        NSString *updateQuery = [NSString stringWithFormat:@"UPDATE ZXIpaModel SET isSigned = 1 WHERE sign = '%@'", ipaModel.sign];
        
        // 获取数据库路径
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dbPath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite", [[NSBundle mainBundle] bundleIdentifier]]];
        
        FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
        [db open];
        BOOL updateResult = [db executeUpdate:updateQuery];
        [db close];
        
        NSLog(@"[IpaManager] 手动更新数据库中的isSigned标志: %@", updateResult ? @"成功" : @"失败");
    } else {
        NSLog(@"[IpaManager] 已签名IPA保存失败: %@", ipaModel.title);
    }
    
    return result;
}

- (NSArray<ZXIpaModel *> *)allSignedIpas {
    NSLog(@"[IpaManager] 获取所有已签名IPA");
    
    // 使用固定的suite名称，而不是使用bundle identifier
    [[NSUserDefaults standardUserDefaults] addSuiteNamed:@"IpaDownloadToolUserDefaults"];
    
    // 查询所有已签名的IPA
    NSArray<ZXIpaModel *> *signedIpas = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 1"];
    
    NSLog(@"[IpaManager] 使用isSigned=1查询找到%lu个已签名IPA", (unsigned long)signedIpas.count);
    
    // 如果没有找到已签名IPA，尝试使用其他查询方式
    if (signedIpas.count == 0) {
        NSLog(@"[IpaManager] 尝试使用替代查询方法");
        
        // 尝试查询标题包含"已签名"的IPA
        NSArray<ZXIpaModel *> *titleSignedIpas = [ZXIpaModel zx_dbQuaryWhere:@"title LIKE '%已签名%'"];
        NSLog(@"[IpaManager] 使用title LIKE查询找到%lu个已签名IPA", (unsigned long)titleSignedIpas.count);
        
        if (titleSignedIpas.count > 0) {
            signedIpas = titleSignedIpas;
        } else {
            // 尝试查询路径包含"SignedIpa"的IPA
            NSArray<ZXIpaModel *> *pathSignedIpas = [ZXIpaModel zx_dbQuaryWhere:@"localPath LIKE '%SignedIpa%'"];
            NSLog(@"[IpaManager] 使用localPath LIKE查询找到%lu个已签名IPA", (unsigned long)pathSignedIpas.count);
            
            if (pathSignedIpas.count > 0) {
                signedIpas = pathSignedIpas;
            } else {
                // 尝试查询所有IPA，然后过滤已签名的
                NSArray<ZXIpaModel *> *allIpas = [ZXIpaModel zx_dbQuaryAll];
                NSMutableArray<ZXIpaModel *> *filteredIpas = [NSMutableArray array];
                
                NSLog(@"[IpaManager] 查询到总共%lu个IPA，开始过滤", (unsigned long)allIpas.count);
                
                for (ZXIpaModel *ipa in allIpas) {
                    NSLog(@"[IpaManager] 检查IPA: %@, isSigned: %d, 路径: %@", ipa.title, ipa.isSigned, ipa.localPath);
                    
                    // 检查是否为已签名IPA
                    if (ipa.isSigned || 
                        (ipa.title && [ipa.title containsString:@"已签名"]) || 
                        (ipa.localPath && [ipa.localPath containsString:@"SignedIpa"])) {
                        
                        // 确保isSigned标志设置正确
                        ipa.isSigned = YES;
                        [ipa zx_dbSave]; // 更新数据库记录
                        
                        [filteredIpas addObject:ipa];
                        NSLog(@"[IpaManager] 找到已签名IPA: %@", ipa.title);
                    }
                }
                
                signedIpas = filteredIpas;
                NSLog(@"[IpaManager] 替代查询找到%lu个已签名IPA", (unsigned long)signedIpas.count);
            }
        }
    }
    
    // 过滤掉文件不存在的IPA
    NSMutableArray<ZXIpaModel *> *validIpas = [NSMutableArray array];
    NSMutableSet<NSString *> *processedPaths = [NSMutableSet set]; // 用于跟踪已处理的文件路径
    
    for (ZXIpaModel *ipa in signedIpas) {
        NSLog(@"[IpaManager] 检查IPA文件: %@, 路径: %@, isSigned: %d", ipa.title, ipa.localPath, ipa.isSigned);
        
        // 检查是否已处理过这个路径
        if (ipa.localPath && ![processedPaths containsObject:ipa.localPath]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:ipa.localPath]) {
                [validIpas addObject:ipa];
                [processedPaths addObject:ipa.localPath]; // 记录已处理的路径
                NSLog(@"[IpaManager] 文件存在，添加到有效列表: %@", ipa.localPath);
            } else {
                NSLog(@"[IpaManager] 警告: IPA文件不存在，将从列表中移除: %@", ipa.localPath);
                // 从数据库中删除不存在的文件记录
                [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipa.sign]];
            }
        } else {
            NSLog(@"[IpaManager] 警告: 跳过重复的IPA路径: %@", ipa.localPath);
        }
    }
    
    // 按签名时间排序（最新的在前面）
    [validIpas sortUsingComparator:^NSComparisonResult(ZXIpaModel *obj1, ZXIpaModel *obj2) {
        if (obj1.signedTime && obj2.signedTime) {
            return [obj2.signedTime compare:obj1.signedTime];
        } else if (obj1.signedTime) {
            return NSOrderedAscending;
        } else if (obj2.signedTime) {
            return NSOrderedDescending;
        } else {
            return [obj2.time compare:obj1.time];
        }
    }];
    
    NSLog(@"[IpaManager] 返回%lu个有效的已签名IPA", (unsigned long)validIpas.count);
    
    return validIpas;
}

- (BOOL)deleteSignedIpa:(ZXIpaModel *)ipaModel {
    NSLog(@"[IpaManager] 删除已签名IPA: %@", ipaModel.title);
    
    if (!ipaModel) {
        NSLog(@"[IpaManager] 错误: IPA模型为空");
        return NO;
    }
    
    // 删除文件
    NSString *filePath = ipaModel.localPath;
    if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error = nil;
        BOOL fileDeleted = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        
        if (!fileDeleted) {
            NSLog(@"[IpaManager] 删除文件失败: %@", error.localizedDescription);
        } else {
            NSLog(@"[IpaManager] 文件已删除: %@", filePath);
        }
    }
    
    // 从数据库中删除
    BOOL result = [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
    
    if (result) {
        NSLog(@"[IpaManager] 已签名IPA从数据库删除成功");
    } else {
        NSLog(@"[IpaManager] 已签名IPA从数据库删除失败");
    }
    
    return result;
}

@end 