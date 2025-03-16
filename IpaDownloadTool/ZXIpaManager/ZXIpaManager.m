//
//  ZXIpaManager.m
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import "ZXIpaManager.h"
#import "NSString+ZXMD5.h"

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
    
    // 保存到数据库
    BOOL result = [ipaModel zx_dbSave];
    
    if (result) {
        NSLog(@"[IpaManager] 已签名IPA保存成功: %@", ipaModel.title);
    } else {
        NSLog(@"[IpaManager] 已签名IPA保存失败: %@", ipaModel.title);
    }
    
    return result;
}

- (NSArray<ZXIpaModel *> *)allSignedIpas {
    NSLog(@"[IpaManager] 获取所有已签名IPA");
    
    // 查询所有已签名的IPA
    NSArray<ZXIpaModel *> *signedIpas = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 1"];
    
    NSLog(@"[IpaManager] 找到%lu个已签名IPA", (unsigned long)signedIpas.count);
    
    return signedIpas;
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