#import "ZXIpaImportVC.h"
#import "ZXFileManage.h"
#import "ZXIpaModel.h"
#import "ZXIpaCell.h"
#import "ZXIpaDetailVC.h"
#import "ZXIpaManager.h"
#import <objc/runtime.h>
#import "NSString+ZXMD5.h"
#import "SSZipArchive.h"
#import "ZXCertificateManager.h"
#import "ZXCertificateManageVC.h"
#import "MBProgressHUD.h"
#import "ALToastView.h"
#import <FMDB/FMDB.h>

@implementation ZXIpaImportVC

#pragma mark - UIDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:nil];
    
    // 确保导入目录存在
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:importedIpaPath]) {
        NSError *createDirError = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:importedIpaPath withIntermediateDirectories:YES attributes:nil error:&createDirError];
        if (createDirError) {
            NSLog(@"创建导入目录失败: %@", createDirError.localizedDescription);
        } else {
            NSLog(@"成功创建导入目录: %@", importedIpaPath);
        }
    }
    
    // 在主线程显示加载指示器
    dispatch_async(dispatch_get_main_queue(), ^{
        [ALToastView showToastWithText:@"正在导入文件..."];
    });
    
    // 在后台线程处理文件
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSURL *url in urls) {
            // 获取安全访问权限
            BOOL securityAccessGranted = NO;
            #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
            if (@available(iOS 11.0, *)) {
                securityAccessGranted = [url startAccessingSecurityScopedResource];
            }
            #endif
            
            @try {
                // 获取文件名
                NSString *fileName = [url lastPathComponent];
                NSLog(@"正在处理文件: %@", fileName);
                
                // 检查是否是IPA文件
                if (![fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                    NSLog(@"不支持的文件类型: %@", fileName.pathExtension);
                    continue;
                }
                
                // 创建安全的文件名
                NSString *safeFileName = [self createSafeFileName:fileName];
                NSString *destinationPath = [importedIpaPath stringByAppendingPathComponent:safeFileName];
                
                // 如果目标文件已存在，先删除
                if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
                    NSError *removeError = nil;
                    if (![[NSFileManager defaultManager] removeItemAtPath:destinationPath error:&removeError]) {
                        NSLog(@"删除已存在的文件失败: %@", removeError.localizedDescription);
                    continue;
                }
                }
                
                // 复制文件到导入目录
                NSError *copyError = nil;
                if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destinationPath] error:&copyError]) {
                NSLog(@"成功导入文件到: %@", destinationPath);
                
                // 解析IPA文件
                ZXIpaModel *ipaModel = [self parseIpaFile:destinationPath];
                if (ipaModel) {
                        // 确保设置正确的本地路径
                        ipaModel.localPath = destinationPath;
                        NSLog(@"设置IPA文件本地路径为: %@", destinationPath);
                        
                        // 确保设置了唯一标识符
                        if (!ipaModel.sign) {
                            NSString *orgSign = [NSString stringWithFormat:@"%@_%@_%@", 
                                                ipaModel.bundleId, 
                                                ipaModel.version, 
                                                [self currentTimeString]];
                            ipaModel.sign = [orgSign md5Str];
                            NSLog(@"生成唯一标识: %@", ipaModel.sign);
                        }
                        
                        // 确保设置了时间
                        if (!ipaModel.time || [ipaModel.time isEqualToString:@"未知日期"]) {
                            ipaModel.time = [self currentTimeString];
                    }
                    
                    // 保存到数据库
                    [self saveIpaInfoToDatabase:ipaModel];
                        
                        // 缓存文件大小
                        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:destinationPath error:nil];
                        if (attributes) {
                            long long fileSize = [attributes fileSize];
                            NSString *sizeStr = [self formatFileSize:fileSize];
                            NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
                            [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:fileSizeKey];
                            [[NSUserDefaults standardUserDefaults] synchronize];
                        }
                        
                        // 添加到列表
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @synchronized (self.ipaList) {
                                [self.ipaList addObject:ipaModel];
                                [self.tableView reloadData];
                                [self hideEmptyView];
                            }
                        });
                    
                    NSLog(@"成功解析并保存IPA信息: %@", ipaModel.title);
                } else {
                        NSLog(@"解析IPA文件失败");
                }
                } else {
                    NSLog(@"复制文件失败: %@", copyError.localizedDescription);
                }
            } @finally {
                // 停止访问安全资源
                #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                if (@available(iOS 11.0, *)) {
                if (securityAccessGranted) {
                    [url stopAccessingSecurityScopedResource];
                }
                }
                #endif
            }
        }
        
        // 在主线程更新UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [ALToastView showToastWithText:@"文件导入完成"];
            
            // 强制同步数据库
            [[NSUserDefaults standardUserDefaults] synchronize];
        });
    });
}

// 创建安全的文件名
- (NSString *)createSafeFileName:(NSString *)fileName {
    // 确保文件名不为空
    if (!fileName || fileName.length == 0) {
        return @"unknown.ipa";
    }
    
    // 解码URL编码
    NSString *decodedName = [fileName stringByRemovingPercentEncoding] ?: fileName;
    
    // 替换不安全的字符
    NSCharacterSet *illegalChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*:|\"<>"];
    NSMutableString *safeName = [NSMutableString stringWithString:decodedName];
    
    for (NSInteger i = safeName.length - 1; i >= 0; i--) {
        unichar c = [safeName characterAtIndex:i];
        if ([illegalChars characterIsMember:c]) {
            [safeName replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
        }
    }
    
    // 确保扩展名为.ipa
    if (![safeName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
        if (safeName.pathExtension.length > 0) {
            safeName = [NSMutableString stringWithString:[safeName stringByDeletingPathExtension]];
        }
        safeName = [NSMutableString stringWithString:[safeName stringByAppendingPathExtension:@"ipa"]];
    }
    
    NSLog(@"原始文件名: %@, 安全文件名: %@", fileName, safeName);
    return safeName;
}

#pragma mark - 加载本地IPA文件
- (void)loadLocalIpaFiles {
    NSLog(@"[加载] 开始加载本地IPA文件");
    
    // 初始化或清空IPA列表
    if (!self.ipaList) {
        self.ipaList = [NSMutableArray array];
        NSLog(@"[加载] 创建新的IPA列表数组");
    } else {
        [self.ipaList removeAllObjects];
        NSLog(@"[加载] 清空现有IPA列表");
    }
    
    // 获取导入IPA的目录路径
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    NSLog(@"[加载] IPA文件导入目录: %@", importedIpaPath);
    
    // 确保导入IPA的目录存在
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        [ZXFileManage creatDirWithPath:importedIpaPath];
        NSLog(@"[加载] 创建导入IPA目录");
    }
    
    // 从数据库中加载所有IPA记录，不限制是否已签名
    NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryAll];
    NSLog(@"[加载] 从数据库中加载了%lu个IPA记录", (unsigned long)dbIpaModels.count);
    
    // 获取ImportedIpa目录中的所有文件
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *importedFiles = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
    
    if (error) {
        NSLog(@"[加载] 读取ImportedIpa目录失败: %@", error.localizedDescription);
    } else {
        NSLog(@"[加载] ImportedIpa目录中有%lu个文件", (unsigned long)importedFiles.count);
        
        // 创建文件名到路径的映射
        NSMutableDictionary *fileNameToPath = [NSMutableDictionary dictionary];
        for (NSString *fileName in importedFiles) {
            if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:fileName];
                fileNameToPath[fileName] = fullPath;
            }
        }
        
        // 处理每个数据库记录
    for (ZXIpaModel *ipaModel in dbIpaModels) {
        // 检查是否是直接引用的外部文件
        BOOL isExternalFile = [ipaModel.bundleId hasPrefix:@"direct."];
        
        if (isExternalFile) {
            NSLog(@"[加载] 处理外部文件记录: %@", ipaModel.bundleId);
            // 从NSUserDefaults获取书签数据
            NSString *bookmarkKey = [NSString stringWithFormat:@"bookmark_%@", ipaModel.bundleId];
            NSData *bookmarkData = [[NSUserDefaults standardUserDefaults] objectForKey:bookmarkKey];
            
            if (bookmarkData) {
                NSLog(@"[加载] 尝试恢复书签: %@", bookmarkKey);
                
                NSError *bookmarkError = nil;
                BOOL stale = NO;
                NSURL *fileURL = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                              options:NSURLBookmarkResolutionWithoutUI
                                                    relativeToURL:nil
                                              bookmarkDataIsStale:&stale
                                                            error:&bookmarkError];
                
                if (bookmarkError) {
                    NSLog(@"[加载] 解析书签失败: %@", bookmarkError.localizedDescription);
                    // 删除无效的书签和数据库记录
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:bookmarkKey];
                    [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
                    continue;
                }
                
                if (stale) {
                    NSLog(@"[加载] 书签已过期，需要更新");
                    // 此处可以尝试更新书签，但通常会失败，因为需要用户重新授权
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:bookmarkKey];
                    [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
                    continue;
                }
                
                    BOOL accessGranted = NO;
                    
                    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                    if (@available(iOS 11.0, *)) {
                        accessGranted = [fileURL startAccessingSecurityScopedResource];
                    }
                    #endif
                
                @try {
                    if (accessGranted) {
                        NSString *path = [fileURL path];
                        NSLog(@"[加载] 成功访问外部文件: %@", path);
                        
                        // 检查文件是否仍然存在
                        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                            NSLog(@"[加载] 外部文件仍然存在，添加到列表");
                            
                            // 更新文件路径（以防万一）
                            ipaModel.localPath = path;
                            ipaModel.downloadUrl = [fileURL absoluteString];
                            
                                // 从缓存中获取文件大小
                                NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
                                NSString *sizeStr = [[NSUserDefaults standardUserDefaults] objectForKey:fileSizeKey];
                                
                                if (!sizeStr) {
                                    // 如果缓存中没有，重新获取文件大小
                            NSError *attributesError = nil;
                            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&attributesError];
                            
                            if (!attributesError && attributes) {
                                // 更新文件大小信息
                                long long fileSize = [attributes fileSize];
                                        sizeStr = [self formatFileSize:fileSize];
                                        
                                        // 缓存文件大小
                                        [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:fileSizeKey];
                                        [[NSUserDefaults standardUserDefaults] synchronize];
                                    }
                                }
                                
                                // 在自定义属性中存储文件大小字符串
                                objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            
                            [self.ipaList addObject:ipaModel];
                        } else {
                            NSLog(@"[加载] 外部文件不再存在，删除书签和数据库记录");
                            [[NSUserDefaults standardUserDefaults] removeObjectForKey:bookmarkKey];
                            [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
                        }
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[加载] 处理书签时发生异常: %@", exception);
                } @finally {
                        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                        if (@available(iOS 11.0, *)) {
                    if (accessGranted) {
                        [fileURL stopAccessingSecurityScopedResource];
                    }
                        }
                        #endif
                }
            } else {
                NSLog(@"[加载] 未找到书签数据，从数据库中删除记录");
                [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
            }
        } else {
            // 处理复制到沙盒的IPA文件
            NSLog(@"[加载] 处理本地IPA文件: %@, 路径: %@", ipaModel.title, ipaModel.localPath);
            
                BOOL fileExists = [ZXFileManage fileExistWithPath:ipaModel.localPath];
                
                if (!fileExists) {
                    // 尝试在ImportedIpa目录中查找文件
                    NSString *fileName = [ipaModel.localPath lastPathComponent];
                    NSString *alternativePath = [importedIpaPath stringByAppendingPathComponent:fileName];
                    
                    if ([ZXFileManage fileExistWithPath:alternativePath]) {
                        NSLog(@"[加载] 在ImportedIpa目录中找到文件: %@", alternativePath);
                        ipaModel.localPath = alternativePath;
                        fileExists = YES;
                        
                        // 更新数据库中的路径
                        [ipaModel zx_dbSave];
                    } else {
                        // 尝试在ImportedIpa目录中查找任何IPA文件
                        for (NSString *existingFileName in fileNameToPath.allKeys) {
                            // 检查是否包含相同的bundleId或应用名称
                            if ([existingFileName containsString:ipaModel.bundleId] || 
                                [existingFileName containsString:ipaModel.title]) {
                                NSLog(@"[加载] 找到类似文件: %@", existingFileName);
                                NSString *similarPath = fileNameToPath[existingFileName];
                                ipaModel.localPath = similarPath;
                                fileExists = YES;
                                
                                // 更新数据库中的路径
                                [ipaModel zx_dbSave];
                                break;
                            }
                        }
                    }
                }
                
                if (fileExists) {
                // 文件存在，添加到列表
                NSLog(@"[加载] 文件存在，添加到列表");
                    
                    // 从缓存中获取文件大小
                    NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
                    NSString *sizeStr = [[NSUserDefaults standardUserDefaults] objectForKey:fileSizeKey];
                    
                    if (!sizeStr) {
                        // 如果缓存中没有，重新获取文件大小
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:ipaModel.localPath error:nil];
                if (attributes) {
                    // 更新文件大小信息
                    long long fileSize = [attributes fileSize];
                            sizeStr = [self formatFileSize:fileSize];
                            
                            // 缓存文件大小
                            [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:fileSizeKey];
                            [[NSUserDefaults standardUserDefaults] synchronize];
                        }
                    }
                    
                    // 在自定义属性中存储文件大小字符串
                    objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                [self.ipaList addObject:ipaModel];
            } else {
                    NSLog(@"[加载] 文件不存在，但保留数据库记录以防文件在其他位置");
                    // 不再立即删除数据库记录，而是保留记录
                }
            }
        }
    }
    
    // 检查是否有ImportedIpa目录中的文件没有对应的数据库记录
    for (NSString *fileName in importedFiles) {
            if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:fileName];
            
            // 检查是否已经在列表中
            BOOL found = NO;
            for (ZXIpaModel *model in self.ipaList) {
                if ([model.localPath isEqualToString:fullPath]) {
                    found = YES;
                        break;
                    }
                }
                
            if (!found) {
                NSLog(@"[加载] 发现未记录的IPA文件: %@，尝试解析并添加", fileName);
                
                // 解析IPA文件
                ZXIpaModel *newModel = [self parseIpaFile:fullPath];
                if (newModel) {
                    // 设置本地路径
                    newModel.localPath = fullPath;
                    
                    // 设置时间
                    if (!newModel.time) {
                        newModel.time = [self currentTimeString];
                    }
                    
                    // 生成唯一标识
                    if (!newModel.sign) {
                        NSString *orgSign = [NSString stringWithFormat:@"%@_%@_%@", 
                                            newModel.bundleId, 
                                            newModel.version, 
                                            [self currentTimeString]];
                        newModel.sign = [orgSign md5Str];
                    }
                    
                    // 保存到数据库
                    [self saveIpaInfoToDatabase:newModel];
                    
                    // 添加到列表
                    [self.ipaList addObject:newModel];
                    NSLog(@"[加载] 成功添加未记录的IPA文件: %@", newModel.title);
                }
            }
        }
    }
    
        [self.tableView reloadData];
        
        // 如果没有IPA文件，显示提示
        if (self.ipaList.count == 0) {
            [self showEmptyView];
        } else {
            [self hideEmptyView];
        }
}

#pragma mark - 解析IPA文件
- (ZXIpaModel *)parseIpaFile:(NSString *)filePath {
    NSLog(@"[解析] 开始解析IPA文件: %@", filePath);
    
    // 获取文件名和哈希值作为缓存键
    NSString *fileName = [filePath lastPathComponent];
    NSString *fileHash = [self fileHashForPath:filePath];
    NSString *cacheKey = [NSString stringWithFormat:@"ipaCache_%@", fileHash];
    
    NSLog(@"[解析] 文件名: %@, 哈希值: %@", fileName, fileHash);
    
    // 检查缓存
    NSDictionary *cachedData = [[NSUserDefaults standardUserDefaults] objectForKey:cacheKey];
    
    // 获取文件修改时间
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    NSTimeInterval modificationTime = [modificationDate timeIntervalSince1970];
    
    // 如果有缓存且文件未被修改，直接使用缓存
    if (cachedData && [cachedData[@"modificationTime"] doubleValue] == modificationTime) {
        NSLog(@"[解析] 从缓存加载IPA信息 (文件未修改)");
        ZXIpaModel *ipaModel = [[ZXIpaModel alloc] init];
        ipaModel.title = cachedData[@"title"];
        ipaModel.version = cachedData[@"version"];
        ipaModel.bundleId = cachedData[@"bundleId"];
        ipaModel.iconUrl = cachedData[@"iconUrl"];
        ipaModel.downloadUrl = cachedData[@"downloadUrl"];
        ipaModel.fromPageUrl = cachedData[@"fromPageUrl"];
        ipaModel.time = cachedData[@"time"];
        ipaModel.sign = cachedData[@"sign"];
    ipaModel.localPath = filePath;
        
        // 更新文件大小缓存
        NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
        NSString *sizeStr = [[NSUserDefaults standardUserDefaults] objectForKey:fileSizeKey];
        if (sizeStr) {
            objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        
        return ipaModel;
    }
    
    NSLog(@"[解析] 缓存无效或文件已修改，开始解析IPA文件");
    
    // 创建临时目录
    NSString *tempDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDirPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    @try {
    // 解压IPA文件
        BOOL unzipSuccess = [SSZipArchive unzipFileAtPath:filePath toDestination:tempDirPath];
        if (!unzipSuccess) {
            NSLog(@"[解析] 解压IPA文件失败");
            return nil;
        }
        
        NSLog(@"[解析] 成功解压IPA文件到: %@", tempDirPath);
        
        // 查找Payload目录
        NSString *payloadPath = [tempDirPath stringByAppendingPathComponent:@"Payload"];
        NSArray *payloadContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
        
        if (payloadContents.count == 0) {
            NSLog(@"[解析] Payload目录为空");
            return nil;
        }
        
        // 查找.app目录
                NSString *appDirName = nil;
        for (NSString *item in payloadContents) {
            if ([item.pathExtension isEqualToString:@"app"]) {
                appDirName = item;
                        break;
                    }
                }
                
        if (!appDirName) {
            NSLog(@"[解析] 未找到.app目录");
            return nil;
        }
        
                    NSString *appPath = [payloadPath stringByAppendingPathComponent:appDirName];
        NSLog(@"[解析] 找到应用目录: %@", appPath);
                    
        // 获取Info.plist路径
                    NSString *infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    
        if (![[NSFileManager defaultManager] fileExistsAtPath:infoPlistPath]) {
            NSLog(@"[解析] Info.plist文件不存在");
            return nil;
        }
        
        // 读取Info.plist
        NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        if (!infoPlist) {
            NSLog(@"[解析] 无法读取Info.plist");
            return nil;
        }
        
        // 提取应用信息
        NSString *bundleId = infoPlist[@"CFBundleIdentifier"];
        NSString *version = infoPlist[@"CFBundleShortVersionString"];
        NSString *title = infoPlist[@"CFBundleDisplayName"] ?: infoPlist[@"CFBundleName"];
        
        if (!bundleId || !version || !title) {
            NSLog(@"[解析] 缺少必要的应用信息");
            return nil;
        }
        
        NSLog(@"[解析] 从Info.plist获取到应用信息 - 名称: %@, Bundle ID: %@, 版本: %@", title, bundleId, version);
        
        // 创建IPA模型
        ZXIpaModel *ipaModel = [[ZXIpaModel alloc] init];
        ipaModel.title = title;
        ipaModel.version = version;
        ipaModel.bundleId = bundleId;
        ipaModel.localPath = filePath;
        ipaModel.time = [self currentTimeString];
        
        // 生成唯一标识
        NSString *uniqueString = [NSString stringWithFormat:@"%@_%@", bundleId, version];
        ipaModel.sign = [uniqueString md5Str];
        
        // 尝试提取应用图标
        NSString *iconPath = [self extractAppIconFromPath:appPath forBundleId:bundleId];
        if (iconPath) {
            ipaModel.iconUrl = iconPath;
        }
        
        // 缓存解析结果
        NSMutableDictionary *cacheDict = [NSMutableDictionary dictionary];
        cacheDict[@"title"] = ipaModel.title;
        cacheDict[@"version"] = ipaModel.version;
        cacheDict[@"bundleId"] = ipaModel.bundleId;
        cacheDict[@"iconUrl"] = ipaModel.iconUrl ?: @"";
        cacheDict[@"downloadUrl"] = ipaModel.downloadUrl ?: @"";
        cacheDict[@"fromPageUrl"] = ipaModel.fromPageUrl ?: @"";
        cacheDict[@"time"] = ipaModel.time;
        cacheDict[@"sign"] = ipaModel.sign;
        cacheDict[@"modificationTime"] = @(modificationTime);
        
        [[NSUserDefaults standardUserDefaults] setObject:cacheDict forKey:cacheKey];
        
        // 缓存文件大小
        NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
        NSString *sizeStr = [self formatFileSize:[attributes fileSize]];
        [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:fileSizeKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // 在自定义属性中存储文件大小字符串
        objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSLog(@"[解析] IPA解析完成，已缓存结果");
        return ipaModel;
    }
    @catch (NSException *exception) {
        NSLog(@"[解析] 解析过程中发生异常: %@", exception);
        return nil;
    }
    @finally {
        // 清理临时目录
        [[NSFileManager defaultManager] removeItemAtPath:tempDirPath error:nil];
    }
}

// 提取应用图标
- (NSString *)extractAppIconFromPath:(NSString *)appPath forBundleId:(NSString *)bundleId {
    // 常见的图标文件名
                                NSArray *commonIconNames = @[
        @"AppIcon60x60@2x.png",
        @"AppIcon60x60@3x.png",
        @"Icon-60@2x.png",
        @"Icon-60@3x.png",
        @"Icon.png",
        @"Icon@2x.png",
        @"DisplayIcon.png"
    ];
    
    // 首先检查常见的图标文件名
    for (NSString *iconName in commonIconNames) {
        NSString *iconPath = [appPath stringByAppendingPathComponent:iconName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
            NSLog(@"[解析] 找到图标文件: %@", iconPath);
                            
                            // 创建AppIcons目录
                            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                            NSString *iconsDir = [documentsPath stringByAppendingPathComponent:@"AppIcons"];
                            
            if (![[NSFileManager defaultManager] fileExistsAtPath:iconsDir]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:iconsDir withIntermediateDirectories:YES attributes:nil error:nil];
                            }
                            
                            // 为图标生成唯一文件名
            NSString *iconFileName = [NSString stringWithFormat:@"%@_%.0f.png", 
                                     bundleId ?: [[NSUUID UUID] UUIDString], 
                                     [NSDate date].timeIntervalSince1970];
                            NSString *destIconPath = [iconsDir stringByAppendingPathComponent:iconFileName];
                            
            // 复制图标文件
                                    NSError *copyError = nil;
                                    [[NSFileManager defaultManager] copyItemAtPath:iconPath toPath:destIconPath error:&copyError];
                                    
                                    if (!copyError) {
                                        NSLog(@"[解析] 成功复制应用图标到: %@", destIconPath);
                return destIconPath;
                                    } else {
                                        NSLog(@"[解析] 复制图标失败: %@", copyError.localizedDescription);
                                    }
                                }
                            }
                            
    // 如果没有找到常见图标，尝试在Info.plist中查找
    // 这部分代码可以根据需要添加
    
    return nil;
}

// 计算文件哈希值
- (NSString *)fileHashForPath:(NSString *)filePath {
    // 使用文件路径和修改时间作为哈希输入
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    NSString *hashInput = [NSString stringWithFormat:@"%@_%f", filePath, [modificationDate timeIntervalSince1970]];
    return [hashInput md5Str];
}

// 格式化文件大小
- (NSString *)formatFileSize:(unsigned long long)fileSize {
    NSString *sizeStr;
    if (fileSize > 1024 * 1024 * 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f GB", fileSize / 1024.0 / 1024.0 / 1024.0];
    } else if (fileSize > 1024 * 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f MB", fileSize / 1024.0 / 1024.0];
    } else if (fileSize > 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f KB", fileSize / 1024.0];
    } else {
        sizeStr = [NSString stringWithFormat:@"%llu B", fileSize];
    }
    return sizeStr;
}

- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - 生命周期方法
- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"[初始化] 开始初始化IPA导入页面");
    
    // 检查SSZipArchive是否可用
    if (NSClassFromString(@"SSZipArchive")) {
        NSLog(@"[初始化] SSZipArchive库可用");
    } else {
        NSLog(@"[初始化] 警告: SSZipArchive库不可用，将无法解压IPA文件");
    }
    
    // 初始化UI
    [self setupUI];
    
    // 验证并创建必要的目录
    [self verifyAndCreateDirectories];
    
    // 创建IPA列表数组
    if (!self.ipaList) {
        self.ipaList = [NSMutableArray array];
        NSLog(@"[初始化] 创建IPA列表数组");
    }
    
    // 恢复可能丢失的IPA文件
    [self recoverMissingIpaFiles];
    
    // 首次加载IPA文件
    [self initialLoadIpaFiles];
    
    // 注册通知，监听应用进入前台事件
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationWillEnterForeground:) 
                                                 name:UIApplicationWillEnterForegroundNotification 
                                               object:nil];
    
    NSLog(@"[初始化] 初始化完成，列表中IPA文件数量: %lu", (unsigned long)self.ipaList.count);
}

- (void)dealloc {
    // 移除通知观察者
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    NSLog(@"[生命周期] IPA导入页面将要显示");
    
    // 每次页面显示时重新加载IPA列表
    [self loadLocalIpaFiles];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"[生命周期] 视图已显示，列表中IPA文件数量: %lu", (unsigned long)self.ipaList.count);
    
    // 如果没有IPA文件，显示导入提示
    if (self.ipaList.count == 0) {
        NSLog(@"[生命周期] 没有IPA文件，显示导入提示");
        [ALToastView showToastWithText:@"请点击底部按钮导入IPA文件"];
    }
}

#pragma mark - 应用进入前台通知
- (void)applicationWillEnterForeground:(NSNotification *)notification {
    NSLog(@"[生命周期] 应用将要进入前台");
    
    // 恢复可能丢失的IPA文件
    [self recoverMissingIpaFiles];
    
    // 重新加载IPA列表
    [self loadLocalIpaFiles];
}

#pragma mark - 数据加载方法
// 首次加载IPA文件（完整加载）
- (void)initialLoadIpaFiles {
    NSLog(@"[加载] 开始首次加载本地IPA文件");
    
    // 记录加载开始时间
    NSDate *startTime = [NSDate date];
    
    // 加载本地IPA文件
    [self loadLocalIpaFiles];
    
    // 计算加载耗时
    NSTimeInterval loadTime = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"[加载] 首次加载完成，耗时: %.2f秒", loadTime);
    
    // 保存最后加载时间戳
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate date].timeIntervalSince1970 
                                              forKey:@"LastIpaLoadTimestamp"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 增量加载IPA文件（只处理新文件）
- (void)incrementalLoadIpaFiles {
    NSLog(@"[加载] 开始增量加载本地IPA文件");
    
    // 记录加载开始时间
    NSDate *startTime = [NSDate date];
    
    // 获取导入IPA的目录路径
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保导入IPA的目录存在
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        [ZXFileManage creatDirWithPath:importedIpaPath];
        NSLog(@"[加载] 创建导入IPA目录");
    }
    
    // 获取目录中的所有文件
    NSError *error = nil;
    NSArray *fileList = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:importedIpaPath error:&error];
    
    if (error) {
        NSLog(@"[加载] 读取目录失败: %@", error.localizedDescription);
        return;
    }
    
    // 获取上次加载时间
    NSTimeInterval lastLoadTime = [[NSUserDefaults standardUserDefaults] doubleForKey:@"LastIpaLoadTimestamp"];
    
    // 标记是否有变化
    BOOL hasChanges = NO;
    
    // 检查是否有新文件或修改的文件
    for (NSString *fileName in fileList) {
        if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSString *filePath = [importedIpaPath stringByAppendingPathComponent:fileName];
            
            // 获取文件修改时间
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            NSDate *modificationDate = attributes[NSFileModificationDate];
            
            // 如果文件是新的或已修改
            if (modificationDate.timeIntervalSince1970 > lastLoadTime) {
                NSLog(@"[加载] 发现新文件或已修改文件: %@", fileName);
                
                // 检查这个文件是否已经在列表中
                BOOL fileExists = NO;
                for (ZXIpaModel *existModel in self.ipaList) {
                    if ([existModel.localPath isEqualToString:filePath]) {
                        fileExists = YES;
                        break;
                    }
                }
                
                if (!fileExists) {
                    // 解析并添加到列表
                    ZXIpaModel *ipaModel = [self parseIpaFile:filePath];
                    if (ipaModel) {
                        [self.ipaList addObject:ipaModel];
                        // 保存到数据库
                        [self saveIpaInfoToDatabase:ipaModel];
                        hasChanges = YES;
                        NSLog(@"[加载] 成功添加新文件: %@", ipaModel.title);
                    }
                }
            }
        }
    }
    
    // 检查数据库中是否有已删除的文件
    NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 0 OR isSigned IS NULL"];
    for (ZXIpaModel *ipaModel in dbIpaModels) {
        if (![ZXFileManage fileExistWithPath:ipaModel.localPath]) {
            // 文件已不存在，从数据库中删除
            NSLog(@"[加载] 文件不存在，从数据库中删除记录: %@", ipaModel.localPath);
            [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
            
            // 从列表中移除
            for (NSInteger i = 0; i < self.ipaList.count; i++) {
                ZXIpaModel *model = self.ipaList[i];
                if ([model.sign isEqualToString:ipaModel.sign]) {
                    [self.ipaList removeObjectAtIndex:i];
                    hasChanges = YES;
                    break;
                }
            }
        }
    }
    
    // 如果有变化，刷新UI
    if (hasChanges) {
        NSLog(@"[加载] 检测到变化，刷新UI");
        [self.tableView reloadData];
        
        // 如果没有IPA文件，显示提示
        if (self.ipaList.count == 0) {
            [self showEmptyView];
        } else {
            [self hideEmptyView];
        }
    }
    
    // 计算加载耗时
    NSTimeInterval loadTime = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"[加载] 增量加载完成，耗时: %.2f秒", loadTime);
    
    // 更新最后加载时间戳
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate date].timeIntervalSince1970 
                                              forKey:@"LastIpaLoadTimestamp"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 判断是否需要刷新数据
- (BOOL)shouldRefreshData {
    // 获取上次加载时间
    NSTimeInterval lastLoadTime = [[NSUserDefaults standardUserDefaults] doubleForKey:@"LastIpaLoadTimestamp"];
    
    // 如果没有加载过，需要刷新
    if (lastLoadTime == 0) {
        return YES;
    }
    
    // 获取导入IPA的目录路径
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 如果目录不存在，需要刷新
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        return YES;
    }
    
    // 获取目录修改时间
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:importedIpaPath error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    
    // 如果目录修改时间晚于上次加载时间，需要刷新
    if (modificationDate.timeIntervalSince1970 > lastLoadTime) {
        return YES;
    }
    
    // 如果列表为空但数据库中有记录，需要刷新
    if (self.ipaList.count == 0) {
        NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 0 OR isSigned IS NULL"];
        if (dbIpaModels.count > 0) {
            return YES;
        }
    }
    
    // 默认不需要刷新
    return NO;
}

#pragma mark - 验证并创建必要的目录
- (void)verifyAndCreateDirectories {
    NSLog(@"[初始化] 验证并创建必要的目录");
    
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // 检查并创建ImportedIpa目录
    if (![fileManager fileExistsAtPath:importedIpaPath]) {
        NSLog(@"[初始化] 创建ImportedIpa目录");
        if (![fileManager createDirectoryAtPath:importedIpaPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"[初始化] 创建ImportedIpa目录失败: %@", error.localizedDescription);
        } else {
            NSLog(@"[初始化] 成功创建ImportedIpa目录");
        }
    } else {
        NSLog(@"[初始化] ImportedIpa目录已存在");
        
        // 检查目录权限
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:importedIpaPath error:&error];
        if (error) {
            NSLog(@"[初始化] 获取ImportedIpa目录属性失败: %@", error.localizedDescription);
        } else {
            NSNumber *permissions = [attributes objectForKey:NSFilePosixPermissions];
            NSLog(@"[初始化] ImportedIpa目录权限: %@", permissions);
            
            // 确保目录有写入权限
            if (![fileManager isWritableFileAtPath:importedIpaPath]) {
                NSLog(@"[初始化] 警告: ImportedIpa目录没有写入权限");
                
                // 尝试修改权限
                NSMutableDictionary *newAttributes = [NSMutableDictionary dictionaryWithDictionary:attributes];
                [newAttributes setObject:@(0755) forKey:NSFilePosixPermissions];
                
                if (![fileManager setAttributes:newAttributes ofItemAtPath:importedIpaPath error:&error]) {
                    NSLog(@"[初始化] 修改ImportedIpa目录权限失败: %@", error.localizedDescription);
                } else {
                    NSLog(@"[初始化] 成功修改ImportedIpa目录权限");
                }
            }
        }
    }
    
    // 检查目录是否可写
    if ([fileManager isWritableFileAtPath:importedIpaPath]) {
        NSLog(@"[初始化] ImportedIpa目录可写");
    } else {
        NSLog(@"[初始化] 警告: ImportedIpa目录不可写");
    }
}

#pragma mark - 导入IPA文件
- (void)importIpaFile {
    NSLog(@"开始导入IPA文件");
    
    // 在iOS 14及更高版本上，我们需要请求临时完全访问权限才能访问文件系统
    if (@available(iOS 14.0, *)) {
        // 创建文档选择器，仅选择IPA文件
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.itunes.ipa"] inMode:UIDocumentPickerModeImport];
        documentPicker.delegate = self;
        documentPicker.allowsMultipleSelection = YES;
        documentPicker.shouldShowFileExtensions = YES;
        
        [self presentViewController:documentPicker animated:YES completion:^{
            NSLog(@"显示文档选择器");
        }];
    } else {
        // iOS 13及更早版本
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.itunes.ipa"] inMode:UIDocumentPickerModeImport];
        documentPicker.delegate = self;
        documentPicker.allowsMultipleSelection = YES;
        
        [self presentViewController:documentPicker animated:YES completion:^{
            NSLog(@"显示文档选择器");
        }];
    }
}

#pragma mark - 上传IPA文件到服务器
- (void)uploadIpaFile:(ZXIpaModel *)ipaModel {
    // 检查文件是否存在
    if (!ipaModel || !ipaModel.localPath) {
        NSLog(@"无效的IPA模型或路径");
        return;
    }
    
    NSString *filePath = ipaModel.localPath;
    NSURL *fileURL = nil;
    
    // 检查是否为外部文件（通过URL字符串判断）
    if (ipaModel.downloadUrl && [ipaModel.downloadUrl hasPrefix:@"file://"]) {
        fileURL = [NSURL URLWithString:ipaModel.downloadUrl];
    } else {
        fileURL = [NSURL fileURLWithPath:filePath];
    }
    
    NSLog(@"准备上传文件: %@", fileURL);
    
    // 如果是外部文件，需要先获取访问权限
    BOOL isExternalFile = [ipaModel.bundleId hasPrefix:@"direct."];
    BOOL securityAccessGranted = NO;
    
    if (isExternalFile) {
        // 尝试从保存的书签恢复访问权限
        NSString *bookmarkKey = [NSString stringWithFormat:@"bookmark_%@", ipaModel.bundleId];
        NSData *bookmarkData = [[NSUserDefaults standardUserDefaults] objectForKey:bookmarkKey];
        
        if (bookmarkData) {
            // 尝试解析书签
            NSError *bookmarkError = nil;
            BOOL stale = NO;
            NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                           options:NSURLBookmarkResolutionWithoutUI
                                                     relativeToURL:nil
                                               bookmarkDataIsStale:&stale
                                                             error:&bookmarkError];
            
            if (!bookmarkError && resolvedURL) {
                fileURL = resolvedURL; // 使用解析后的URL
                #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
                if (@available(iOS 11.0, *)) {
                securityAccessGranted = [fileURL startAccessingSecurityScopedResource];
                NSLog(@"成功获取安全访问权限: %@", securityAccessGranted ? @"是" : @"否");
                }
                #endif
            } else {
                NSLog(@"无法解析书签: %@", bookmarkError ? bookmarkError.localizedDescription : @"未知错误");
            }
        } else {
            NSLog(@"未找到书签数据");
        }
    }
    
    @try {
        // 这里是上传文件到服务器的代码
        // 你需要使用NSURLSession或其他网络API来实现
        // 例如：
        
        // 1. 创建请求
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
        [request setURL:[NSURL URLWithString:@"https://your-server.com/upload"]];
        [request setHTTPMethod:@"POST"];
        
        // 2. 设置请求体（这里需要根据你的服务器API进行调整）
        NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
        NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        
        // 3. 创建请求体数据
        NSMutableData *body = [NSMutableData data];
        
        // 添加文件数据
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", [filePath lastPathComponent]] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        
        // 读取文件数据
        NSError *readError = nil;
        NSData *fileData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:&readError];
        
        if (readError || !fileData) {
            NSLog(@"读取文件失败: %@", readError ? readError.localizedDescription : @"未知错误");
            return;
        }
        
        [body appendData:fileData];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        
        // 设置请求体
        [request setHTTPBody:body];
        
        // 4. 创建会话任务
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"上传失败: %@", error.localizedDescription);
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSLog(@"上传完成，状态码: %ld", (long)httpResponse.statusCode);
                
                // 解析响应数据
                if (data) {
                    NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    NSLog(@"服务器响应: %@", responseDict);
                }
            }
        }];
        
        // 5. 开始上传任务
        [task resume];
        
    } @catch (NSException *exception) {
        NSLog(@"上传文件时发生异常: %@", exception);
    } @finally {
        // 如果是外部文件并且获取了安全访问权限，需要释放
        #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
        if (@available(iOS 11.0, *)) {
        if (isExternalFile && securityAccessGranted) {
            [fileURL stopAccessingSecurityScopedResource];
        }
        }
        #endif
    }
}

- (void)setupUI {
    self.title = @"IPA导入";
    self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
    
    // 创建表格视图
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 160; // 确保单元格有足够的高度显示所有内容
    [self.view addSubview:self.tableView];
    
    // 注册cell
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"IpaCell"];
    
    // 创建导入按钮
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importButton setTitle:@"导入IPA文件" forState:UIControlStateNormal];
    [self.importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.importButton.backgroundColor = MainColor;
    self.importButton.layer.cornerRadius = 25;
    [self.importButton addTarget:self action:@selector(importIpaFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importButton];
    
    // 创建清空按钮
    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearButton setTitle:@"清空所有IPA" forState:UIControlStateNormal];
    [clearButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearButton.backgroundColor = [UIColor systemRedColor];
    clearButton.layer.cornerRadius = 25;
    [clearButton addTarget:self action:@selector(showClearConfirmation) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clearButton];
    
    // 设置自动布局约束
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 表格视图约束
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
        [self.tableView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.importButton.topAnchor constant:-10],
        
        // 导入按钮约束
        [self.importButton.heightAnchor constraintEqualToConstant:50],
        [self.importButton.widthAnchor constraintEqualToConstant:150],
        [self.importButton.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-160],
        [self.importButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        
        // 清空按钮约束
        [clearButton.heightAnchor constraintEqualToConstant:50],
        [clearButton.widthAnchor constraintEqualToConstant:150],
        [clearButton.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:160],
        [clearButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
    
    NSLog(@"UI设置完成，表格视图、导入按钮和清空按钮已创建");
}

// 显示清空确认对话框
- (void)showClearConfirmation {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"确认清空"
                                                                             message:@"您确定要清空所有IPA文件信息吗？此操作不可撤销。"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确认清空"
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction * _Nonnull action) {
        [self clearAllIpaFiles];
    }];
    
    [alertController addAction:cancelAction];
    [alertController addAction:confirmAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

// 清空所有IPA文件
- (void)clearAllIpaFiles {
    NSLog(@"[清空] 开始清空所有IPA文件信息");
    
    // 显示进度提示
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在清空IPA文件...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 在后台线程执行清空操作
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        
        // 1. 清空ImportedIpa目录
        NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
        if ([fileManager fileExistsAtPath:importedIpaPath]) {
            NSError *error = nil;
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
            
            if (!error) {
                for (NSString *item in contents) {
                    NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:item];
                    [fileManager removeItemAtPath:fullPath error:nil];
                    NSLog(@"[清空] 删除文件: %@", fullPath);
                }
            }
        }
        
        // 2. 清空ZXIpaDownloadedArr目录
        // NSString *downloadedIpaPath = [documentsPath stringByAppendingPathComponent:@"ZXIpaDownloadedArr"];
        if ([fileManager fileExistsAtPath:importedIpaPath]) {
            NSError *error = nil;
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
            
            if (!error) {
                for (NSString *item in contents) {
                    NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:item];
                    [fileManager removeItemAtPath:fullPath error:nil];
                    NSLog(@"[清空] 删除文件夹: %@", fullPath);
                }
            }
        }
        
        // 3. 清空数据库中所有非签名的IPA记录
        [ZXIpaModel zx_dbDropWhere:@"isSigned = 0 OR isSigned IS NULL"];
        NSLog(@"[清空] 从数据库中删除所有非签名的IPA记录");
        
        // 4. 清空用户偏好设置中的书签和缓存
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *allDefaults = [defaults dictionaryRepresentation];
        
        for (NSString *key in allDefaults.allKeys) {
            if ([key hasPrefix:@"bookmark_"] || [key hasPrefix:@"ipaCache_"] || [key hasPrefix:@"fileSize_"]) {
                [defaults removeObjectForKey:key];
                NSLog(@"[清空] 删除用户偏好设置项: %@", key);
            }
        }
        [defaults synchronize];
        
        // 5. 清空内存中的列表
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.ipaList removeAllObjects];
            [self.tableView reloadData];
            
            // 显示空视图
            [self showEmptyView];
            
            // 隐藏进度提示
            [hud hideAnimated:YES];
            
            // 显示成功提示
            [ALToastView showToastWithText:@"已清空所有IPA文件信息"];
        });
    });
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.ipaList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IpaCell" forIndexPath:indexPath];
    
    // 清除原有内容
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    
    // 设置卡片视图
    UIView *cardView = [[UIView alloc] init];
    cardView.backgroundColor = [UIColor whiteColor];
    cardView.layer.cornerRadius = 10;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 2);
    cardView.layer.shadowRadius = 4;
    cardView.layer.shadowOpacity = 0.1;
    [cell.contentView addSubview:cardView];
    
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [cardView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
        [cardView.leftAnchor constraintEqualToAnchor:cell.contentView.leftAnchor constant:16],
        [cardView.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
        [cardView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8]
    ]];
    
    // 获取当前IPA模型
    ZXIpaModel *ipaModel = self.ipaList[indexPath.row];
    NSLog(@"[单元格] 显示IPA信息 - 行: %ld, 标题: %@, 本地路径: %@", (long)indexPath.row, ipaModel.title, ipaModel.localPath);
    NSLog(@"[单元格] 图标路径: %@", ipaModel.iconUrl ?: @"无图标路径");
    
    // 设置应用图标
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.backgroundColor = [UIColor lightGrayColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 10;
    iconView.layer.masksToBounds = YES;
    [cardView addSubview:iconView];
    
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:10],
        [iconView.leftAnchor constraintEqualToAnchor:cardView.leftAnchor constant:10],
        [iconView.widthAnchor constraintEqualToConstant:60],
        [iconView.heightAnchor constraintEqualToConstant:60]
    ]];
    
    // 尝试设置图标
    if (ipaModel.iconUrl && ipaModel.iconUrl.length > 0) {
        NSLog(@"[单元格] 尝试加载图标: %@", ipaModel.iconUrl);
        // 检查文件是否存在
        if ([ZXFileManage fileExistWithPath:ipaModel.iconUrl]) {
            NSLog(@"[单元格] 图标文件存在，尝试读取");
            UIImage *iconImage = [UIImage imageWithContentsOfFile:ipaModel.iconUrl];
            if (iconImage) {
                NSLog(@"[单元格] 成功加载图标，大小: %.0f x %.0f", iconImage.size.width, iconImage.size.height);
                iconView.image = iconImage;
            } else {
                NSLog(@"[单元格] 加载图标失败，文件存在但无法转换为图像");
                [self setPlaceholderIcon:iconView forTitle:ipaModel.title];
            }
        } else {
            NSLog(@"[单元格] 图标文件不存在: %@", ipaModel.iconUrl);
            [self setPlaceholderIcon:iconView forTitle:ipaModel.title];
        }
    } else {
        NSLog(@"[单元格] 没有图标URL，使用占位图标");
        [self setPlaceholderIcon:iconView forTitle:ipaModel.title];
    }
    
    // 设置应用名称
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = ipaModel.title ?: @"未知应用";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.numberOfLines = 2;
    [cardView addSubview:titleLabel];
    
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:10],
        [titleLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:10],
        [titleLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-10],
    ]];
    
    // 设置Bundle ID标签
    UILabel *bundleIdLabel = [[UILabel alloc] init];
    bundleIdLabel.text = [NSString stringWithFormat:@"Bundle ID: %@", ipaModel.bundleId ?: @"未知"];
    bundleIdLabel.font = [UIFont systemFontOfSize:12];
    bundleIdLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:bundleIdLabel];
    
    bundleIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [bundleIdLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:5],
        [bundleIdLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:10],
        [bundleIdLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-10],
    ]];
    
    // 设置版本标签
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = [NSString stringWithFormat:@"版本: %@", ipaModel.version ?: @"未知"];
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:versionLabel];
    
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [versionLabel.topAnchor constraintEqualToAnchor:bundleIdLabel.bottomAnchor constant:5],
        [versionLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:10],
        [versionLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-10],
    ]];
    
    // 设置文件大小标签
    UILabel *sizeLabel = [[UILabel alloc] init];
    NSString *sizeStr = objc_getAssociatedObject(ipaModel, "fileSize");
    sizeLabel.text = [NSString stringWithFormat:@"大小: %@", sizeStr ?: @"未知"];
    sizeLabel.font = [UIFont systemFontOfSize:12];
    sizeLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:sizeLabel];
    
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [sizeLabel.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:5],
        [sizeLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:10],
        [sizeLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-10],
    ]];
    
    // 设置导入时间标签
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.text = [NSString stringWithFormat:@"导入时间: %@", ipaModel.time ?: @"未知"];
    timeLabel.font = [UIFont systemFontOfSize:12];
    timeLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:timeLabel];
    
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [timeLabel.topAnchor constraintEqualToAnchor:sizeLabel.bottomAnchor constant:5],
        [timeLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:10],
        [timeLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-10],
        [timeLabel.bottomAnchor constraintLessThanOrEqualToAnchor:cardView.bottomAnchor constant:-10]
    ]];
    
    // 设置cell
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    NSLog(@"[单元格] 完成配置单元格");
    
    return cell;
}

// 设置占位图标
- (void)setPlaceholderIcon:(UIImageView *)iconView forTitle:(NSString *)title {
    // 创建一个纯色背景的图像，上面显示应用名称的首字母或首个汉字
    CGSize size = CGSizeMake(50, 50);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    
    // 绘制圆角矩形背景
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:10];
    [[UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0] setFill];
    [path fill];
    
    // 获取应用名称的首字母或汉字
    NSString *initial = @"?";
    if (title.length > 0) {
        if ([title canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            // 英文名取第一个字母
            initial = [title substringToIndex:1].uppercaseString;
        } else {
            // 中文名取第一个字
            initial = [title substringToIndex:1];
        }
    }
    
    // 设置字体属性
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:24],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    // 计算文字大小以居中显示
    CGSize textSize = [initial sizeWithAttributes:attributes];
    CGPoint point = CGPointMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2);
    
    // 绘制文字
    [initial drawAtPoint:point withAttributes:attributes];
    
    // 获取图像并设置
    UIImage *placeholderImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    iconView.image = placeholderImage;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row < self.ipaList.count) {
        ZXIpaModel *ipaModel = self.ipaList[indexPath.row];
        
        // 创建操作菜单
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:ipaModel.title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
        
        // 添加签名选项
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"签名"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // 调用签名方法
            [self signIpaFile:ipaModel];
        }]];
        
        // 如果已经有安装链接，添加直接安装选项
        if (ipaModel.installLink && ipaModel.installLink.length > 0) {
            [actionSheet addAction:[UIAlertAction actionWithTitle:@"直接安装"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
                // 调用直接安装方法
                [self installIpaWithLink:ipaModel.installLink];
            }]];
        }
        
        // 添加分享选项
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"分享"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // 分享IPA文件
            [self shareIpaFile:ipaModel];
        }]];
        
        // 添加删除选项
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"删除"
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // 删除文件和数据库记录
            [self deleteIpaFile:ipaModel atIndexPath:indexPath];
        }]];
        
        // 添加取消按钮
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil]];
        
        // 在iPad上需要设置弹出位置
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            actionSheet.popoverPresentationController.sourceView = cell;
            actionSheet.popoverPresentationController.sourceRect = cell.bounds;
        }
        
        [self presentViewController:actionSheet animated:YES completion:nil];
    }
}

// 删除IPA文件
- (void)deleteIpaFile:(ZXIpaModel *)ipaModel atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"[删除] 开始删除IPA文件: %@", ipaModel.title);
    
    BOOL isExternalFile = [ipaModel.bundleId hasPrefix:@"direct."];
    
    // 只删除数据库记录，不删除原始文件
    if (isExternalFile) {
        NSLog(@"[删除] 删除外部文件记录，不删除原始文件");
        // 删除书签
        NSString *bookmarkKey = [NSString stringWithFormat:@"bookmark_%@", ipaModel.bundleId];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:bookmarkKey];
    } else {
        // 对于复制到沙盒的文件，可以删除实际文件
        if ([ZXFileManage fileExistWithPath:ipaModel.localPath]) {
            NSLog(@"[删除] 删除本地文件: %@", ipaModel.localPath);
            [ZXFileManage delFileWithPath:ipaModel.localPath];
        } else {
            NSLog(@"[删除] 文件不存在，只删除数据库记录: %@", ipaModel.localPath);
        }
    }
    
    // 删除缓存
    NSString *fileName = [ipaModel.localPath lastPathComponent];
    NSString *cacheKey = [NSString stringWithFormat:@"ipaCache_%@", [fileName md5Str]];
    NSString *fileSizeKey = [NSString stringWithFormat:@"fileSize_%@", ipaModel.sign];
    
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:cacheKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:fileSizeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // 从数据库删除记录
    [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
    
    // 更新UI
    [self.ipaList removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    
    // 检查是否需要显示空视图
    if (self.ipaList.count == 0) {
        [self showEmptyView];
    }
    
    NSLog(@"[删除] 删除完成");
}

#pragma mark - 保存IPA信息到数据库
- (void)saveIpaInfoToDatabase:(ZXIpaModel *)ipaModel {
    if (!ipaModel) {
        return;
    }
    
    NSLog(@"[保存] 开始保存IPA信息到数据库: %@", ipaModel.title);
    
    // 1. 检查是否已存在相同的IPA
    NSArray *sameArr = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"bundleId='%@' AND version='%@'", ipaModel.bundleId, ipaModel.version]];
    if (sameArr.count) {
        // 如果已存在，则删除旧记录
        NSLog(@"[保存] 数据库中已存在相同Bundle ID和版本的记录，删除旧记录: %@", ipaModel.bundleId);
        [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@' AND version='%@'", ipaModel.bundleId, ipaModel.version]];
    }
    
    // 2. 确保时间字段有值
    NSDate *date = [NSDate date];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    // 如果时间未设置，则使用当前时间
    if (!ipaModel.time || [ipaModel.time isEqualToString:@"未知日期"]) {
        ipaModel.time = [format stringFromDate:date];
    }
    
    // 3. 检查localPath是否指向ImportedIpa目录
    NSString *filePath = ipaModel.localPath;
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保ImportedIpa目录存在
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        [ZXFileManage creatDirWithPath:importedIpaPath];
        NSLog(@"[保存] 创建ImportedIpa目录");
    }
    
    // 如果是本地导入的文件，确保localPath使用ImportedIpa目录中的路径
    if ([filePath hasPrefix:importedIpaPath]) {
        NSLog(@"[保存] 文件已在ImportedIpa目录中: %@", filePath);
    } else {
        // 检查文件是否已复制到ImportedIpa目录
        NSString *fileName = [filePath lastPathComponent];
        NSString *importedFilePath = [importedIpaPath stringByAppendingPathComponent:fileName];
        
        if ([ZXFileManage fileExistWithPath:importedFilePath]) {
            NSLog(@"[保存] 文件已在ImportedIpa目录中，更新localPath: %@", importedFilePath);
            ipaModel.localPath = importedFilePath;
        } else {
            // 检查文件是否存在于原始路径
            if ([ZXFileManage fileExistWithPath:filePath]) {
                NSLog(@"[保存] 文件存在于原始路径，尝试复制到ImportedIpa目录: %@", filePath);
                
                // 尝试复制文件到ImportedIpa目录
                NSError *copyError = nil;
                if ([[NSFileManager defaultManager] copyItemAtPath:filePath toPath:importedFilePath error:&copyError]) {
                    NSLog(@"[保存] 成功复制文件到ImportedIpa目录: %@", importedFilePath);
                    ipaModel.localPath = importedFilePath;
                } else {
                    NSLog(@"[保存] 复制文件失败: %@", copyError.localizedDescription);
                    // 如果复制失败，继续使用原始路径
                }
            } else {
                NSLog(@"[保存] 警告: 文件不存在于原始路径，尝试查找替代路径");
                
                // 尝试在ImportedIpa目录中查找同名文件
                NSFileManager *fileManager = [NSFileManager defaultManager];
                NSError *error = nil;
                NSArray *files = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
                
                if (!error) {
                    for (NSString *file in files) {
                        if ([file.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                            NSString *possiblePath = [importedIpaPath stringByAppendingPathComponent:file];
                            NSLog(@"[保存] 找到可能的IPA文件: %@", possiblePath);
                            ipaModel.localPath = possiblePath;
                            break;
                        }
                    }
                }
            }
        }
    }
    
    // 确保localPath是绝对路径
    if (![ipaModel.localPath hasPrefix:@"/"]) {
        NSLog(@"[保存] 警告: localPath不是绝对路径，尝试修复");
        if ([ipaModel.localPath hasPrefix:@"~"]) {
            // 替换波浪号为用户目录
            NSString *homePath = NSHomeDirectory();
            ipaModel.localPath = [ipaModel.localPath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:homePath];
        } else {
            // 假设是相对于Documents目录的路径
            ipaModel.localPath = [documentsPath stringByAppendingPathComponent:ipaModel.localPath];
        }
        NSLog(@"[保存] 修复后的路径: %@", ipaModel.localPath);
    }
    
    // 4. 生成唯一标识
    if (!ipaModel.sign) {
        NSString *orgSign = [NSString stringWithFormat:@"%@_%@_%@", 
                              ipaModel.bundleId, 
                              ipaModel.version, 
                              [self currentTimeString]];
        ipaModel.sign = [orgSign md5Str];
        NSLog(@"[保存] 生成唯一标识: %@", ipaModel.sign);
    }
    
    // 5. 检查是否有图标路径
    if (ipaModel.iconUrl) {
        NSLog(@"[保存] 保存图标路径到数据库: %@", ipaModel.iconUrl);
    } else {
        NSLog(@"[保存] 没有找到图标路径");
    }
    
    // 6. 将IPA信息保存到数据库
    BOOL saveResult = [ipaModel zx_dbSave];
    
    if (saveResult) {
        NSLog(@"[保存] 成功保存IPA信息到数据库");
    } else {
        NSLog(@"[保存] 保存IPA信息到数据库失败");
    }
}

#pragma mark - 检查文件系统状态
- (void)checkFileSystemStatus {
    NSLog(@"======检查文件系统状态======");
    
    // 检查数据库中的IPA记录
    NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryAll];
    NSLog(@"数据库中IPA记录数: %lu", (unsigned long)dbIpaModels.count);
    
    // 检查沙盒目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 检查ImportedIpa目录是否存在
    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:importedIpaPath isDirectory:&isDirectory];
    NSLog(@"ImportedIpa目录状态: 存在=%@, 是目录=%@", exists ? @"是" : @"否", isDirectory ? @"是" : @"否");
    
    if (exists && isDirectory) {
        // 获取目录中的文件
        NSError *error = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:importedIpaPath error:&error];
        
        if (error) {
            NSLog(@"读取ImportedIpa目录失败: %@", error.localizedDescription);
        } else {
            NSLog(@"ImportedIpa目录中文件数: %lu", (unsigned long)files.count);
            
            // 检查每个文件的状态
            for (NSString *fileName in files) {
                NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:fileName];
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:&error];
                
                if (error) {
                    NSLog(@"获取文件属性失败: %@, 路径: %@", error.localizedDescription, fullPath);
                } else {
                    unsigned long long fileSize = [attributes fileSize];
                    NSDate *modDate = [attributes fileModificationDate];
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    
                    NSLog(@"文件: %@, 大小: %llu bytes, 修改时间: %@", 
                          fileName, 
                          fileSize, 
                          [formatter stringFromDate:modDate]);
                }
            }
        }
    }
    
    // 检查用户偏好设置中的书签
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    NSMutableArray *bookmarkKeys = [NSMutableArray array];
    
    for (NSString *key in allDefaults.allKeys) {
        if ([key hasPrefix:@"bookmark_"]) {
            [bookmarkKeys addObject:key];
        }
    }
    
    NSLog(@"用户偏好设置中的书签数: %lu", (unsigned long)bookmarkKeys.count);
    
    for (NSString *key in bookmarkKeys) {
        NSData *bookmarkData = [defaults objectForKey:key];
        NSLog(@"书签键: %@, 数据大小: %lu bytes", key, (unsigned long)bookmarkData.length);
    }
    
    NSLog(@"======文件系统状态检查完成======");
} 

#pragma mark - 签名和分享IPA文件
// 签名IPA文件
- (void)signIpaFile:(ZXIpaModel *)ipaModel {
    NSLog(@"[签名流程] ========== 开始签名IPA文件: %@ ==========", ipaModel.title);
    NSLog(@"[签名流程] IPA文件路径: %@", ipaModel.localPath);
    
    // 检查文件是否存在
    if (!ipaModel || !ipaModel.localPath) {
        NSLog(@"[签名流程] 错误: IPA模型或路径为空");
        [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
        return;
    }
    
    // 检查文件是否存在于指定路径
    BOOL fileExists = [ZXFileManage fileExistWithPath:ipaModel.localPath];
    NSLog(@"[签名流程] 文件存在检查: %@", fileExists ? @"是" : @"否");
    
    if (!fileExists) {
        NSLog(@"[签名流程] 原始路径不存在，尝试查找替代路径");
        
        // 1. 尝试在ImportedIpa目录中查找文件
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
        NSString *fileName = [ipaModel.localPath lastPathComponent];
        NSString *alternativePath = [importedIpaPath stringByAppendingPathComponent:fileName];
        
        NSLog(@"[签名流程] 尝试替代路径1: %@", alternativePath);
        
        if ([ZXFileManage fileExistWithPath:alternativePath]) {
            NSLog(@"[签名流程] 在ImportedIpa目录中找到文件");
            ipaModel.localPath = alternativePath;
            fileExists = YES;
        } else {
            // 2. 尝试查找原始目录的父目录
            NSString *originalDirectory = [ipaModel.localPath stringByDeletingLastPathComponent];
            NSString *parentDirectory = [originalDirectory stringByDeletingLastPathComponent];
            NSString *alternativePath2 = [parentDirectory stringByAppendingPathComponent:fileName];
            
            NSLog(@"[签名流程] 尝试替代路径2: %@", alternativePath2);
            
            if ([ZXFileManage fileExistWithPath:alternativePath2]) {
                NSLog(@"[签名流程] 在父目录中找到文件");
                ipaModel.localPath = alternativePath2;
                fileExists = YES;
            } else {
                // 3. 尝试在ZXIpaDownloadedPath目录中查找
                // NSString *downloadedIpaPath = [documentsPath stringByAppendingPathComponent:@"ZXIpaDownloadedArr"];
                NSLog(@"[签名流程] 尝试在下载目录中查找: %@", importedIpaPath);
                
                // 检查下载目录是否存在
                if ([ZXFileManage fileExistWithPath:importedIpaPath]) {
                    // 遍历下载目录下的所有子目录
                    NSFileManager *fileManager = [NSFileManager defaultManager];
                    NSError *error = nil;
                    NSArray *subDirectories = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
                    
                    if (!error && subDirectories.count > 0) {
                        NSLog(@"[签名流程] 在下载目录中找到%lu个子目录", (unsigned long)subDirectories.count);
                        
                        BOOL found = NO;
                        for (NSString *subDir in subDirectories) {
                            NSString *fullSubDir = [importedIpaPath stringByAppendingPathComponent:subDir];
                            
                            // 仅检查目录
                            BOOL isDirectory = NO;
                            if ([fileManager fileExistsAtPath:fullSubDir isDirectory:&isDirectory] && isDirectory) {
                                NSString *possibleIpaPath = [fullSubDir stringByAppendingPathComponent:fileName];
                                NSLog(@"[签名流程] 检查路径: %@", possibleIpaPath);
                                
                                if ([ZXFileManage fileExistWithPath:possibleIpaPath]) {
                                    NSLog(@"[签名流程] 在下载子目录中找到文件!");
                                    ipaModel.localPath = possibleIpaPath;
                                    found = YES;
                                    fileExists = YES;
                                    break;
                                }
                            }
                        }
                        
                        if (!found) {
                            NSLog(@"[签名流程] 错误: 在下载子目录中未找到文件");
                            
                            // 4. 尝试查找实际IPA文件
                            NSLog(@"[签名流程] 开始查找所有IPA文件...");
                            NSMutableArray *allIpaPaths = [NSMutableArray array];
                            [self findAllIpaFilesInDirectory:documentsPath toArray:allIpaPaths];
                            
                            if (allIpaPaths.count > 0) {
                                NSLog(@"[签名流程] 找到%lu个IPA文件:", (unsigned long)allIpaPaths.count);
                                for (NSString *path in allIpaPaths) {
                                    NSLog(@"[签名流程] - %@", path);
                                }
                                
                                // 尝试查找SideStore.ipa
                                NSString *sideStoreIpaPath = nil;
                                for (NSString *path in allIpaPaths) {
                                    if ([[path lastPathComponent] isEqualToString:@"SideStore.ipa"]) {
                                        sideStoreIpaPath = path;
                                        break;
                                    }
                                }
                                
                                if (sideStoreIpaPath) {
                                    NSLog(@"[签名流程] 找到SideStore.ipa，使用它: %@", sideStoreIpaPath);
                                    ipaModel.localPath = sideStoreIpaPath;
                                } else {
                                    // 使用第一个找到的IPA文件
                                    ipaModel.localPath = allIpaPaths.firstObject;
                                    NSLog(@"[签名流程] 使用找到的第一个IPA文件: %@", ipaModel.localPath);
                                }
                                fileExists = YES;
                            } else {
                                NSLog(@"[签名流程] 错误: 找不到任何IPA文件");
                                [ALToastView showToastWithText:@"找不到任何IPA文件，请重新导入"];
                                return;
                            }
                        }
                    } else {
                        NSLog(@"[签名流程] 错误: 无法读取下载目录或目录为空");
                        [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
                        return;
                    }
                } else {
                    NSLog(@"[签名流程] 错误: 下载目录不存在");
                    [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
                    return;
                }
            }
        }
    }
    
    if (!fileExists) {
        NSLog(@"[签名流程] 错误: 经过所有尝试后仍未找到IPA文件");
        [ALToastView showToastWithText:@"无法找到IPA文件，请重新导入"];
        return;
    }
    
    NSLog(@"[签名流程] 最终使用的IPA路径: %@", ipaModel.localPath);
    
    // 获取证书管理器
    ZXCertificateManager *certManager = [ZXCertificateManager sharedManager];
    NSLog(@"[签名流程] 获取证书管理器");
    
    // 获取所有P12证书
    NSArray<ZXCertificateModel *> *p12Certificates = [certManager allP12Certificates];
    NSLog(@"[签名流程] 获取到 %lu 个P12证书", (unsigned long)p12Certificates.count);
    
    // 获取所有描述文件
    NSArray<ZXCertificateModel *> *provisionProfiles = [certManager allProvisionProfiles];
    NSLog(@"[签名流程] 获取到 %lu 个描述文件", (unsigned long)provisionProfiles.count);
    
    // 检查是否有可用的证书
    if (p12Certificates.count == 0) {
        NSLog(@"[签名流程] 错误: 没有可用的P12证书");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无可用证书"
                                                                       message:@"请先导入P12证书"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"去导入证书"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            // 跳转到证书管理页面
            ZXCertificateManageVC *certVC = [[ZXCertificateManageVC alloc] init];
            [self.navigationController pushViewController:certVC animated:YES];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if (provisionProfiles.count == 0) {
        NSLog(@"[签名流程] 错误: 没有可用的描述文件");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无可用描述文件"
                                                                       message:@"请先导入描述文件"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"去导入描述文件"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            // 跳转到证书管理页面
            ZXCertificateManageVC *certVC = [[ZXCertificateManageVC alloc] init];
            [self.navigationController pushViewController:certVC animated:YES];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSLog(@"[签名流程] 存在可用的证书和描述文件，开始处理签名");
    
    // 如果只有一个P12证书，直接使用
    if (p12Certificates.count == 1) {
        ZXCertificateModel *p12Cert = p12Certificates.firstObject;
        NSLog(@"[签名流程] 只有一个P12证书，直接使用: %@", p12Cert.certificateName ?: p12Cert.filename);
        
        // 查找匹配的描述文件
        NSMutableArray *matchingProfiles = [NSMutableArray array];
        for (ZXCertificateModel *profile in provisionProfiles) {
            BOOL isMatching = [certManager verifyP12Certificate:p12Cert withProvisionProfile:profile];
            NSLog(@"[签名流程] 检查描述文件 %@ 是否匹配: %@", profile.certificateName ?: profile.filename, isMatching ? @"是" : @"否");
            if (isMatching) {
                [matchingProfiles addObject:profile];
            }
        }
        
        if (matchingProfiles.count == 0) {
            NSLog(@"[签名流程] 错误: 没有找到与证书匹配的描述文件");
            [ALToastView showToastWithText:@"没有找到与证书匹配的描述文件"];
            return;
        }
        
        if (matchingProfiles.count == 1) {
            // 只有一个匹配的描述文件，直接使用
            ZXCertificateModel *profile = matchingProfiles.firstObject;
            NSLog(@"[签名流程] 只有一个匹配的描述文件，直接使用: %@", profile.certificateName ?: profile.filename);
            
            // 调用签名方法
            NSLog(@"[签名流程] 调用startSigningWithP12:provisionProfile:andIpa:方法");
            [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
        } else {
            // 多个匹配的描述文件，显示选择器
            NSLog(@"[签名流程] 有多个匹配的描述文件 (%lu个)，显示选择器", (unsigned long)matchingProfiles.count);
            
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择描述文件"
                                                                                     message:@"请选择用于签名的描述文件"
                                                                              preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (ZXCertificateModel *profile in matchingProfiles) {
                NSString *profileName = profile.certificateName ?: profile.filename;
                UIAlertAction *action = [UIAlertAction actionWithTitle:profileName
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"[签名流程] 用户选择了描述文件: %@", profileName);
                    [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                }];
                [alertController addAction:action];
            }
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
            [alertController addAction:cancelAction];
            
            // 在iPad上需要设置弹出位置
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                alertController.popoverPresentationController.sourceView = self.view;
                alertController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
                alertController.popoverPresentationController.permittedArrowDirections = 0;
            }
            
            NSLog(@"[签名流程] 显示描述文件选择器");
            [self presentViewController:alertController animated:YES completion:nil];
        }
    } else {
        // 多个P12证书，显示选择器
        NSLog(@"[签名流程] 有多个P12证书 (%lu个)，显示选择器", (unsigned long)p12Certificates.count);
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择证书"
                                                                                 message:@"请选择用于签名的证书"
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
        
        for (ZXCertificateModel *p12Cert in p12Certificates) {
            // 查找匹配的描述文件
            NSMutableArray *matchingProfiles = [NSMutableArray array];
            
            for (ZXCertificateModel *profile in provisionProfiles) {
                if ([certManager verifyP12Certificate:p12Cert withProvisionProfile:profile]) {
                    [matchingProfiles addObject:profile];
                }
            }
            
            // 只有有匹配的描述文件时才添加此证书选项
            if (matchingProfiles.count > 0) {
                NSString *certName = p12Cert.certificateName ?: p12Cert.filename;
                NSString *title = [NSString stringWithFormat:@"%@ (%lu个描述文件)", 
                                  certName,
                                  (unsigned long)matchingProfiles.count];
                
                UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"[签名流程] 用户选择了证书: %@", certName);
                    
                    if (matchingProfiles.count == 1) {
                        // 只有一个匹配的描述文件，直接使用
                        ZXCertificateModel *profile = matchingProfiles.firstObject;
                        NSLog(@"[签名流程] 只有一个匹配的描述文件，直接使用: %@", profile.certificateName ?: profile.filename);
                        [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                    } else {
                        // 多个匹配的描述文件，显示选择器
                        NSLog(@"[签名流程] 有多个匹配的描述文件 (%lu个)，显示选择器", (unsigned long)matchingProfiles.count);
                        
                        UIAlertController *profileController = [UIAlertController alertControllerWithTitle:@"选择描述文件"
                                                                                                   message:@"请选择用于签名的描述文件"
                                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
                        
                        for (ZXCertificateModel *profile in matchingProfiles) {
                            NSString *profileName = profile.certificateName ?: profile.filename;
                            UIAlertAction *profileAction = [UIAlertAction actionWithTitle:profileName
                                                                                    style:UIAlertActionStyleDefault
                                                                                  handler:^(UIAlertAction * _Nonnull action) {
                                NSLog(@"[签名流程] 用户选择了描述文件: %@", profileName);
                                [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                            }];
                            [profileController addAction:profileAction];
                        }
                        
                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
                        [profileController addAction:cancelAction];
                        
                        // 在iPad上需要设置弹出位置
                        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                            profileController.popoverPresentationController.sourceView = self.view;
                            profileController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
                            profileController.popoverPresentationController.permittedArrowDirections = 0;
                        }
                        
                        NSLog(@"[签名流程] 显示描述文件选择器");
                        [self presentViewController:profileController animated:YES completion:nil];
                    }
                }];
                [alertController addAction:action];
            }
        }
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        [alertController addAction:cancelAction];
        
        // 在iPad上需要设置弹出位置
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            alertController.popoverPresentationController.sourceView = self.view;
            alertController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
            alertController.popoverPresentationController.permittedArrowDirections = 0;
        }
        
        NSLog(@"[签名流程] 显示证书选择器");
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

// 选择描述文件
- (void)selectProvisionProfile:(NSArray<ZXCertificateModel *> *)profiles forP12:(ZXCertificateModel *)p12Cert andIpa:(ZXIpaModel *)ipaModel {
    UIAlertController *profileSelector = [UIAlertController alertControllerWithTitle:@"选择描述文件"
                                                                             message:@"请选择用于签名的描述文件"
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 添加描述文件选项
    for (ZXCertificateModel *profile in profiles) {
        NSString *title = profile.certificateName ?: profile.filename;
        
        [profileSelector addAction:[UIAlertAction actionWithTitle:title
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
            [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
        }]];
    }
    
    // 添加取消按钮
    [profileSelector addAction:[UIAlertAction actionWithTitle:@"取消"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
    
    // 在iPad上需要设置弹出位置
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        profileSelector.popoverPresentationController.sourceView = self.view;
        profileSelector.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
        profileSelector.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [self presentViewController:profileSelector animated:YES completion:nil];
}

// 开始签名过程
- (void)startSigningWithP12:(ZXCertificateModel *)p12Cert provisionProfile:(ZXCertificateModel *)profile andIpa:(ZXIpaModel *)ipaModel {
    NSLog(@"[签名上传] ========== 开始上传文件 ==========");
    NSLog(@"[签名上传] P12路径: %@", p12Cert.filepath);
    NSLog(@"[签名上传] 描述文件路径: %@", profile.filepath);
    NSLog(@"[签名上传] IPA路径: %@", ipaModel.localPath);
    
    // 获取证书密码
    NSString *p12Password = [[ZXCertificateManager sharedManager] passwordForP12Certificate:p12Cert];
    NSLog(@"[签名上传] P12密码: %@", p12Password ? @"已设置" : @"未设置");
    
    // 检查文件是否存在
    BOOL p12Exists = [[NSFileManager defaultManager] fileExistsAtPath:p12Cert.filepath];
    BOOL provisionExists = [[NSFileManager defaultManager] fileExistsAtPath:profile.filepath];
    BOOL ipaExists = [[NSFileManager defaultManager] fileExistsAtPath:ipaModel.localPath];
    
    NSLog(@"[签名上传] P12文件存在: %@", p12Exists ? @"是" : @"否");
    NSLog(@"[签名上传] 描述文件存在: %@", provisionExists ? @"是" : @"否");
    NSLog(@"[签名上传] IPA文件存在: %@", ipaExists ? @"是" : @"否");
    
    if (!p12Exists || !provisionExists || !ipaExists) {
        NSLog(@"[签名上传] 错误: 文件不存在，中止上传");
        [ALToastView showToastWithText:@"文件不存在，无法上传"];
        return;
    }
    
    // 显示加载指示器
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在上传文件...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 设置上传URL
    NSString *urlString = @"https://cloud.cloudmantoub.online/sign";
    NSLog(@"[签名上传] 上传URL: %@", urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    
    // 创建请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    // 增加超时时间
    [request setTimeoutInterval:600]; // 10分钟超时
    
    // 创建唯一边界字符串
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    NSLog(@"[签名上传] 设置请求边界: %@", boundary);
    
    // 创建请求体
    NSMutableData *body = [NSMutableData data];
    
    // 添加p12文件
    [self appendFileData:body 
                 withName:@"p12" 
                 fileName:@"certificate.p12" 
                 filePath:p12Cert.filepath 
                 boundary:boundary];
    
    // 添加描述文件
    [self appendFileData:body 
                 withName:@"mobileprovision" 
                 fileName:@"profile.mobileprovision" 
                 filePath:profile.filepath 
                 boundary:boundary];
    
    // 添加IPA文件
    [self appendFileData:body 
                 withName:@"ipa" 
                 fileName:@"app.ipa" 
                 filePath:ipaModel.localPath 
                 boundary:boundary];
    
    // 添加密码
    if (p12Password) {
        [self appendTextData:body 
                    withName:@"p12_password" 
                       value:p12Password 
                    boundary:boundary];
        NSLog(@"[签名上传] 已添加P12密码到表单");
    } else {
        NSLog(@"[签名上传] 警告: P12密码为空");
    }
    
    // 添加结束边界
    NSString *boundaryEnd = [NSString stringWithFormat:@"--%@--\r\n", boundary];
    [body appendData:[boundaryEnd dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"[签名上传] 表单数据总大小: %lu bytes", (unsigned long)body.length);
    
    // 设置请求体
    [request setHTTPBody:body];
    
    // 创建会话和任务
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 600; // 10分钟超时
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSLog(@"[签名上传] 开始上传任务");
    
    NSURLSessionDataTask *uploadTask = [session dataTaskWithRequest:request
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
            
            if (error) {
                NSLog(@"[签名上传] 上传错误: %@", error.localizedDescription);
                [ALToastView showToastWithText:[NSString stringWithFormat:@"上传失败: %@", error.localizedDescription]];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[签名上传] 上传完成，状态码: %ld", (long)httpResponse.statusCode);
            NSLog(@"[签名上传] 响应头: %@", httpResponse.allHeaderFields);
            
            if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[签名上传] 服务器响应: %@", responseString);
                
                // 尝试解析JSON
                NSError *jsonError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    NSLog(@"[签名上传] JSON解析错误: %@", jsonError.localizedDescription);
                    [ALToastView showToastWithText:@"签名请求已发送，但无法解析响应"];
                } else {
                    NSLog(@"[签名上传] JSON响应: %@", jsonResponse);
                    
                    // 根据响应显示不同消息并处理下载
                    if ([httpResponse statusCode] >= 200 && [httpResponse statusCode] < 300) {
                        // 尝试获取下载链接
                        NSString *installLink = jsonResponse[@"installLink"];
                        NSString *downloadUrl = jsonResponse[@"downloadUrl"] ?: jsonResponse[@"url"];
                        
                        if (downloadUrl) {
                            NSLog(@"[签名上传] 获取到下载链接: %@", downloadUrl);
                            [self downloadSignedIpa:downloadUrl withOriginalIpa:ipaModel installAfterDownload:YES];
                        } else if (installLink) {
                            NSLog(@"[签名上传] 获取到安装链接: %@", installLink);
                            // 保存安装链接到IPA模型中
                            ipaModel.installLink = installLink;
                            ipaModel.isSigned = YES;
                            ipaModel.signedTime = [self currentTimeString];
                            
                            // 保存更新后的IPA信息到数据库
                            [ipaModel zx_dbSave];
                            
                            // 显示成功消息
                            [ALToastView showToastWithText:@"签名成功，正在安装..."];
                            
                            // 直接调用安装方法
                            [self installIpaWithLink:installLink];
                        } else {
                            [ALToastView showToastWithText:@"签名请求发送成功，请等待签名完成"];
                        }
                    } else {
                        // 尝试获取错误消息
                        NSString *errorMessage = jsonResponse[@"error"] ?: jsonResponse[@"message"] ?: @"签名请求发送失败";
                        [ALToastView showToastWithText:errorMessage];
                    }
                }
            } else {
                NSLog(@"[签名上传] 没有响应数据");
                [ALToastView showToastWithText:@"签名请求已发送，但没有响应数据"];
            }
        });
    }];
    
    [uploadTask resume];
    NSLog(@"[签名上传] 上传任务已启动");
}

// 辅助方法：添加文件数据到表单
- (void)appendFileData:(NSMutableData *)body 
              withName:(NSString *)name 
              fileName:(NSString *)fileName 
              filePath:(NSString *)filePath 
              boundary:(NSString *)boundary {
    
    NSString *boundaryStart = [NSString stringWithFormat:@"--%@\r\n", boundary];
    
    // 添加文件头
    [body appendData:[boundaryStart dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *contentDisposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name, fileName];
    [body appendData:[contentDisposition dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 读取文件数据
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (fileData) {
        [body appendData:fileData];
        NSLog(@"[签名上传] 已添加%@数据到表单，大小: %lu bytes", name, (unsigned long)fileData.length);
    } else {
        NSLog(@"[签名上传] 警告: %@数据为空", name);
    }
    
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

// 辅助方法：添加文本数据到表单
- (void)appendTextData:(NSMutableData *)body 
              withName:(NSString *)name 
                 value:(NSString *)value 
              boundary:(NSString *)boundary {
    
    NSString *boundaryStart = [NSString stringWithFormat:@"--%@\r\n", boundary];
    
    // 添加文本头
    [body appendData:[boundaryStart dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *contentDisposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", name];
    [body appendData:[contentDisposition dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加文本值
    [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

// 处理大型IPA文件上传
- (void)uploadLargeIpaFileWithP12:(ZXCertificateModel *)p12Cert 
              provisionProfile:(ZXCertificateModel *)profile 
                     ipaModel:(ZXIpaModel *)ipaModel 
                     password:(NSString *)p12Password 
                          hud:(MBProgressHUD *)existingHud {
    
    NSLog(@"[签名上传大文件] ========== 开始大文件上传 ==========");
    
    // 显示加载指示器（如果没有已存在的）
    MBProgressHUD *hud = existingHud;
    if (!hud) {
        hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    }
    hud.label.text = @"正在处理大文件上传...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 创建操作队列进行后台处理
    NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];
    [operationQueue addOperationWithBlock:^{
        // 1. 尝试压缩IPA文件（可选）
        // 在这里，我们不进行实际压缩，因为IPA本身已经是压缩文件
        
        // 2. 使用NSURLSession上传文件而不是加载到内存
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 1800; // 30分钟超时
        configuration.timeoutIntervalForResource = 1800; // 30分钟资源超时
        
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
        
        // 构建请求
        NSURL *url = [NSURL URLWithString:@"https://cloud.cloudmantoub.online/sign"];
        
        // 使用流式上传
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"POST"];
        
        // 设置边界
        NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
        NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        
        // 创建管道
        // NSPipe *pipe = [NSPipe pipe];
        // NSFileHandle *writeHandle = pipe.fileHandleForWriting;
        
        // 创建上传任务
        NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:ipaModel.localPath] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [hud hideAnimated:YES];
                
                if (error) {
                    NSLog(@"[签名上传大文件] 上传错误: %@", error.localizedDescription);
                    [ALToastView showToastWithText:[NSString stringWithFormat:@"大文件上传失败: %@", error.localizedDescription]];
                    return;
                }
                
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSLog(@"[签名上传大文件] 上传完成，状态码: %ld", (long)httpResponse.statusCode);
                
                if (data) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"[签名上传大文件] 服务器响应: %@", responseString);
                    
                    // 尝试解析JSON
                    NSError *jsonError;
                    NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    
                    if (!jsonError && jsonResponse) {
                        // 解析响应
                        NSString *downloadUrl = jsonResponse[@"downloadUrl"] ?: jsonResponse[@"url"];
                        NSString *installLink = jsonResponse[@"installLink"];
                        
                        if (downloadUrl) {
                            [self downloadSignedIpa:downloadUrl withOriginalIpa:ipaModel installAfterDownload:YES];
                        } else if (installLink) {
                            NSLog(@"[签名上传大文件] 获取到安装链接: %@", installLink);
                            // 从installLink中提取plist URL
                            NSString *plistUrlString = nil;
                            NSURLComponents *components = [NSURLComponents componentsWithString:installLink];
                            for (NSURLQueryItem *item in components.queryItems) {
                                if ([item.name isEqualToString:@"url"]) {
                                    plistUrlString = [item.value stringByRemovingPercentEncoding];
                                    break;
                                }
                            }
                            
                            if (plistUrlString) {
                                NSLog(@"[签名上传大文件] 提取到plist URL: %@", plistUrlString);
                                // 下载plist文件以获取真实的IPA下载链接
                                [self downloadPlistAndExtractIpaUrl:plistUrlString withOriginalIpa:ipaModel];
                            } else {
                                [ALToastView showToastWithText:@"签名成功，但无法提取plist URL"];
                            }
                        } else {
                            [ALToastView showToastWithText:@"签名请求已发送，请稍后检查"];
                        }
                    } else {
                        [ALToastView showToastWithText:@"签名请求已发送，但服务器响应格式不正确"];
                    }
                } else {
                    [ALToastView showToastWithText:@"签名请求已发送，但没有收到响应"];
                }
            });
        }];
        
        // 启动上传任务
        [uploadTask resume];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            hud.label.text = @"正在上传IPA文件...";
            hud.detailsLabel.text = @"请耐心等待，这可能需要几分钟";
        });
    }];
    
    NSLog(@"[签名上传大文件] 已添加到操作队列");
}

// 下载签名后的IPA
- (void)downloadSignedIpa:(NSString *)downloadUrl withOriginalIpa:(ZXIpaModel *)originalIpa {
    [self downloadSignedIpa:downloadUrl withOriginalIpa:originalIpa installAfterDownload:NO];
}

// 下载签名后的IPA，带安装选项
- (void)downloadSignedIpa:(NSString *)downloadUrl withOriginalIpa:(ZXIpaModel *)originalIpa installAfterDownload:(BOOL)installAfterDownload {
    NSLog(@"[下载] 开始下载签名后的IPA: %@", downloadUrl);
    
    // 显示加载指示器
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在下载签名后的IPA...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 创建下载任务
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:downloadUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 在主线程更新UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
            
            if (error) {
                NSLog(@"[下载] 下载失败: %@", error.localizedDescription);
                [ALToastView showToastWithText:@"下载签名后的IPA失败"];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[下载] 下载完成，状态码: %ld", (long)httpResponse.statusCode);
            
            if (data) {
                // 创建签名后的IPA保存目录
                NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *signedIpaPath = [documentsPath stringByAppendingPathComponent:@"SignedIpa"];
                
                if (![[NSFileManager defaultManager] fileExistsAtPath:signedIpaPath]) {
                    NSError *createDirError = nil;
                    [[NSFileManager defaultManager] createDirectoryAtPath:signedIpaPath withIntermediateDirectories:YES attributes:nil error:&createDirError];
                    
                    if (createDirError) {
                        NSLog(@"[下载] 创建SignedIpa目录失败: %@", createDirError.localizedDescription);
                        [ALToastView showToastWithText:@"创建签名IPA目录失败"];
                        return;
                    }
                }
                
                // 生成签名后的IPA文件名
                NSString *signedFileName = [NSString stringWithFormat:@"%@_signed_%@.ipa", 
                                           [originalIpa.title stringByDeletingPathExtension],
                                           [self currentTimeString]];
                signedFileName = [signedFileName stringByReplacingOccurrencesOfString:@":" withString:@"-"];
                signedFileName = [signedFileName stringByReplacingOccurrencesOfString:@" " withString:@"_"];
                
                NSString *signedFilePath = [signedIpaPath stringByAppendingPathComponent:signedFileName];
                
                // 保存签名后的IPA文件
                BOOL writeSuccess = [data writeToFile:signedFilePath atomically:YES];
                
                if (writeSuccess) {
                    NSLog(@"[下载] 成功保存签名后的IPA: %@", signedFilePath);
                    
                    // 创建签名后的IPA模型
                    ZXIpaModel *signedIpaModel = [[ZXIpaModel alloc] init];
                    signedIpaModel.title = [NSString stringWithFormat:@"%@ (已签名)", originalIpa.title];
                    signedIpaModel.version = originalIpa.version;
                    signedIpaModel.bundleId = originalIpa.bundleId;
                    signedIpaModel.iconUrl = originalIpa.iconUrl;
                    signedIpaModel.localPath = signedFilePath;
                    signedIpaModel.time = [self currentTimeString];
                    signedIpaModel.isSigned = YES; // 确保设置为已签名
                    signedIpaModel.signedTime = [self currentTimeString];
                    
                    // 生成唯一标识
                    NSString *uniqueString = [NSString stringWithFormat:@"%@_%@_signed_%@", originalIpa.bundleId, originalIpa.version, [self currentTimeString]];
                    signedIpaModel.sign = [uniqueString md5Str];
                    
                    // 创建plist URL
                    NSString *plistUrl = [NSString stringWithFormat:@"https://cloud.cloudmantoub.online/plist/%@", signedIpaModel.sign];
                    NSString *installUrl = [NSString stringWithFormat:@"itms-services://?action=download-manifest&url=%@", 
                                           [plistUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
                    signedIpaModel.installLink = installUrl;
                    
                    NSLog(@"[下载] 准备保存签名后的IPA到数据库，isSigned=%d, 路径=%@", signedIpaModel.isSigned, signedIpaModel.localPath);
                    
                    // 先直接保存到数据库
                    BOOL dbSaveResult = [signedIpaModel zx_dbSave];
                    NSLog(@"[下载] 直接保存到数据库结果: %@", dbSaveResult ? @"成功" : @"失败");
                    
                    // 再使用IpaManager保存已签名IPA
                    BOOL saveResult = [[ZXIpaManager sharedManager] saveSignedIpa:signedIpaModel];
                    
                    if (saveResult || dbSaveResult) {
                        NSLog(@"[下载] 签名后的IPA已成功保存到数据库");
                        
                        if (installAfterDownload) {
                            // 直接安装
                            [ALToastView showToastWithText:@"签名成功，正在安装..."];
                            [self installIpaWithLink:installUrl];
                        } else {
                            [ALToastView showToastWithText:@"签名成功，已保存到已签名IPA列表"];
                            
                            // 跳转到已签名IPA页面
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                UITabBarController *tabBarController = (UITabBarController *)self.navigationController.tabBarController;
                                if (tabBarController) {
                                    // 切换到已签名IPA页面（索引为2）
                                    tabBarController.selectedIndex = 2;
                                }
                            });
                        }
                        
                        // 手动更新数据库中的isSigned标志
                        NSString *updateQuery = [NSString stringWithFormat:@"UPDATE ZXIpaModel SET isSigned = 1 WHERE sign = '%@'", signedIpaModel.sign];
                        
                        // 获取数据库路径
                        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                        NSString *dbPath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite", [[NSBundle mainBundle] bundleIdentifier]]];
                        
                        FMDatabase *db = [FMDatabase databaseWithPath:dbPath];
                        [db open];
                        BOOL updateResult = [db executeUpdate:updateQuery];
                        [db close];
                        
                        NSLog(@"[下载] 手动更新数据库中的isSigned标志: %@", updateResult ? @"成功" : @"失败");
                    } else {
                        NSLog(@"[下载] 保存签名后的IPA到数据库失败");
                        [ALToastView showToastWithText:@"保存签名后的IPA失败"];
                    }
                } else {
                    NSLog(@"[下载] 保存签名后的IPA失败");
                    [ALToastView showToastWithText:@"保存签名后的IPA失败"];
                }
            } else {
                [ALToastView showToastWithText:@"下载签名后的IPA失败，数据为空"];
            }
        });
    }];
    
    // 开始下载任务
    [task resume];
}

// 分享IPA文件
- (void)shareIpaFile:(ZXIpaModel *)ipaModel {
    NSLog(@"分享IPA文件: %@", ipaModel.title);
    
    // 检查文件是否存在
    if (!ipaModel || !ipaModel.localPath || ![ZXFileManage fileExistWithPath:ipaModel.localPath]) {
        [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
        return;
    }
    
    // 创建文件URL
    NSURL *fileURL = [NSURL fileURLWithPath:ipaModel.localPath];
    
    // 创建活动视图控制器
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    
    // 在iPad上需要设置弹出位置
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    }
    
    // 显示分享界面
    [self presentViewController:activityVC animated:YES completion:nil];
} 

#pragma mark - 空视图管理
- (void)showEmptyView {
    // 检查是否已经有空视图
    if ([self.view viewWithTag:1001]) {
        return;
    }
    
    // 创建空视图
    UIView *emptyView = [[UIView alloc] init];
    emptyView.tag = 1001;
    emptyView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:emptyView];
    
    // 设置自动布局约束
    emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [emptyView.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [emptyView.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [emptyView.widthAnchor constraintEqualToConstant:250],
        [emptyView.heightAnchor constraintEqualToConstant:200]
    ]];
    
    // 创建图标
    UIImageView *iconView = [[UIImageView alloc] init];
    if (@available(iOS 13.0, *)) {
        UIImage *image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        iconView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        // 创建一个简单的占位图标
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(60, 60), NO, 0);
        [[UIColor lightGrayColor] setFill];
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(10, 10, 40, 40) cornerRadius:5];
        [path fill];
        UIImage *placeholderImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        iconView.image = placeholderImage;
    }
    iconView.tintColor = [UIColor lightGrayColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [emptyView addSubview:iconView];
    
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
        [iconView.topAnchor constraintEqualToAnchor:emptyView.topAnchor],
        [iconView.widthAnchor constraintEqualToConstant:60],
        [iconView.heightAnchor constraintEqualToConstant:60]
    ]];
    
    // 创建提示文本
    UILabel *messageLabel = [[UILabel alloc] init];
    messageLabel.text = @"没有导入的IPA文件";
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.font = [UIFont systemFontOfSize:16];
    messageLabel.textColor = [UIColor darkGrayColor];
    messageLabel.numberOfLines = 0;
    [emptyView addSubview:messageLabel];
    
    messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [messageLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:20],
        [messageLabel.leftAnchor constraintEqualToAnchor:emptyView.leftAnchor],
        [messageLabel.rightAnchor constraintEqualToAnchor:emptyView.rightAnchor],
    ]];
    
    // 创建提示说明
    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.text = @"点击底部按钮导入IPA文件";
    detailLabel.textAlignment = NSTextAlignmentCenter;
    detailLabel.font = [UIFont systemFontOfSize:14];
    detailLabel.textColor = [UIColor lightGrayColor];
    detailLabel.numberOfLines = 0;
    [emptyView addSubview:detailLabel];
    
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [detailLabel.topAnchor constraintEqualToAnchor:messageLabel.bottomAnchor constant:10],
        [detailLabel.leftAnchor constraintEqualToAnchor:emptyView.leftAnchor],
        [detailLabel.rightAnchor constraintEqualToAnchor:emptyView.rightAnchor],
        [detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:emptyView.bottomAnchor]
    ]];
    
    // 添加动画效果
    emptyView.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        emptyView.alpha = 1;
    }];
    
    NSLog(@"显示空视图");
}

- (void)hideEmptyView {
    // 查找空视图
    UIView *emptyView = [self.view viewWithTag:1001];
    if (!emptyView) {
        return;
    }
    
    // 添加动画效果
    [UIView animateWithDuration:0.3 animations:^{
        emptyView.alpha = 0;
    } completion:^(BOOL finished) {
        [emptyView removeFromSuperview];
    }];
    
    NSLog(@"隐藏空视图");
}

// 递归查找所有IPA文件
- (void)findAllIpaFilesInDirectory:(NSString *)directory toArray:(NSMutableArray *)result {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:directory error:&error];
    
    if (error) {
        NSLog(@"[签名流程] 读取目录失败: %@, 错误: %@", directory, error.localizedDescription);
        return;
    }
    
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) {
            continue; // 跳过隐藏文件
        }
        
        NSString *fullPath = [directory stringByAppendingPathComponent:item];
        BOOL isDirectory = NO;
        
        if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
            if (isDirectory) {
                // 递归遍历子目录
                [self findAllIpaFilesInDirectory:fullPath toArray:result];
            } else {
                // 检查是否是IPA文件
                if ([[item pathExtension] isEqualToString:@"ipa"]) {
                    NSLog(@"[签名流程] 找到IPA文件: %@", fullPath);
                    [result addObject:fullPath];
                }
            }
        }
    }
}

// 处理签名按钮点击
- (void)handleSignAction:(ZXIpaModel *)ipaModel {
    NSLog(@"[签名流程] 用户点击了签名按钮，开始处理签名操作");
    
    // 检查IPA文件是否存在
    if (!ipaModel || !ipaModel.localPath) {
        NSLog(@"[签名流程] 错误: IPA模型或路径为空");
        [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
        return;
    }
    
    // 检查文件是否存在于指定路径
    BOOL fileExists = [ZXFileManage fileExistWithPath:ipaModel.localPath];
    NSLog(@"[签名流程] 原始IPA文件存在检查: %@", fileExists ? @"是" : @"否");
    NSLog(@"[签名流程] 原始IPA路径: %@", ipaModel.localPath);
    
    // 尝试查找SideStore.ipa
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *sideStoreIpaPath = nil;
    
    // 1. 首先在ImportedIpa目录中查找
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    NSString *possiblePath = [importedIpaPath stringByAppendingPathComponent:@"SideStore.ipa"];
    
    if ([ZXFileManage fileExistWithPath:possiblePath]) {
        sideStoreIpaPath = possiblePath;
        NSLog(@"[签名流程] 在ImportedIpa目录中找到SideStore.ipa: %@", sideStoreIpaPath);
    } else {
        // 2. 在下载目录中查找
        // NSString *downloadedIpaPath = [documentsPath stringByAppendingPathComponent:@"ZXIpaDownloadedArr"];
        
        // 查找所有IPA文件
        NSMutableArray *allIpaPaths = [NSMutableArray array];
        [self findAllIpaFilesInDirectory:documentsPath toArray:allIpaPaths];
        
        // 查找SideStore.ipa
        for (NSString *path in allIpaPaths) {
            if ([[path lastPathComponent] isEqualToString:@"SideStore.ipa"]) {
                sideStoreIpaPath = path;
                NSLog(@"[签名流程] 在所有IPA文件中找到SideStore.ipa: %@", sideStoreIpaPath);
                break;
            }
        }
        
        // 如果没有找到SideStore.ipa，使用第一个找到的IPA文件
        if (!sideStoreIpaPath && allIpaPaths.count > 0) {
            sideStoreIpaPath = allIpaPaths.firstObject;
            NSLog(@"[签名流程] 未找到SideStore.ipa，使用第一个IPA文件: %@", sideStoreIpaPath);
        }
    }
    
    // 如果找到了IPA文件，使用它
    if (sideStoreIpaPath) {
        NSLog(@"[签名流程] 使用IPA文件: %@", sideStoreIpaPath);
        
        // 获取证书管理器
        ZXCertificateManager *certManager = [ZXCertificateManager sharedManager];
        
        // 获取所有P12证书
        NSArray<ZXCertificateModel *> *p12Certificates = [certManager allP12Certificates];
        NSLog(@"[签名流程] 获取到 %lu 个P12证书", (unsigned long)p12Certificates.count);
        
        // 获取所有描述文件
        NSArray<ZXCertificateModel *> *provisionProfiles = [certManager allProvisionProfiles];
        NSLog(@"[签名流程] 获取到 %lu 个描述文件", (unsigned long)provisionProfiles.count);
        
        // 检查是否有可用的证书和描述文件
        if (p12Certificates.count > 0 && provisionProfiles.count > 0) {
            // 使用第一个证书和描述文件进行测试
            ZXCertificateModel *p12Cert = p12Certificates.firstObject;
            ZXCertificateModel *profile = provisionProfiles.firstObject;
            
            NSLog(@"[签名流程] 使用证书: %@", p12Cert.certificateName ?: p12Cert.filename);
            NSLog(@"[签名流程] 使用描述文件: %@", profile.certificateName ?: profile.filename);
            
            // 创建临时IPA模型
            ZXIpaModel *tempIpaModel = [[ZXIpaModel alloc] init];
            tempIpaModel.title = @"SideStore";
            tempIpaModel.localPath = sideStoreIpaPath;
            
            // 直接调用上传方法
            NSLog(@"[签名流程] 直接调用上传方法，绕过证书选择器");
            [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:tempIpaModel];
        } else {
            NSLog(@"[签名流程] 错误: 没有可用的证书或描述文件");
            [ALToastView showToastWithText:@"请先导入证书和描述文件"];
        }
    } else {
        NSLog(@"[签名流程] 错误: 找不到任何IPA文件");
        [ALToastView showToastWithText:@"找不到任何IPA文件，请先导入"];
    }
}

// 显示证书选择器
- (void)showCertificateSelectorWithP12Certificates:(NSArray<ZXCertificateModel *> *)p12Certificates 
                                  provisionProfiles:(NSArray<ZXCertificateModel *> *)provisionProfiles 
                                            andIpa:(ZXIpaModel *)ipaModel {
    
    NSLog(@"[证书选择] 显示证书选择器");
    NSLog(@"[证书选择] IPA文件路径: %@", ipaModel.localPath);
    
    // 检查IPA文件是否存在
    BOOL ipaExists = [ZXFileManage fileExistWithPath:ipaModel.localPath];
    NSLog(@"[证书选择] IPA文件存在: %@", ipaExists ? @"是" : @"否");
    
    if (!ipaExists) {
        NSLog(@"[证书选择] IPA文件不存在，尝试查找替代文件");
        
        // 尝试查找SideStore.ipa
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
        NSString *sideStoreIpaPath = [importedIpaPath stringByAppendingPathComponent:@"SideStore.ipa"];
        
        if ([ZXFileManage fileExistWithPath:sideStoreIpaPath]) {
            NSLog(@"[证书选择] 找到SideStore.ipa，使用它: %@", sideStoreIpaPath);
            ipaModel.localPath = sideStoreIpaPath;
            ipaExists = YES;
        } else {
            // 查找ImportedIpa目录中的任何IPA文件
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *error = nil;
            NSArray *files = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
            
            if (!error && files.count > 0) {
                for (NSString *file in files) {
                    if ([file.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                        NSString *ipaPath = [importedIpaPath stringByAppendingPathComponent:file];
                        NSLog(@"[证书选择] 找到IPA文件: %@", ipaPath);
                        ipaModel.localPath = ipaPath;
                        ipaExists = YES;
                        break;
                    }
                }
            }
            
            if (!ipaExists) {
                NSLog(@"[证书选择] 无法找到任何IPA文件");
                [ALToastView showToastWithText:@"无法找到IPA文件，请重新导入"];
                return;
            }
        }
    }
    
    // 如果只有一个P12证书，直接使用
    if (p12Certificates.count == 1) {
        ZXCertificateModel *p12Cert = p12Certificates.firstObject;
        NSLog(@"[证书选择] 只有一个P12证书，直接使用: %@", p12Cert.certificateName ?: p12Cert.filename);
        
        // 查找匹配的描述文件
        NSMutableArray *matchingProfiles = [NSMutableArray array];
        for (ZXCertificateModel *profile in provisionProfiles) {
            BOOL isMatching = [[ZXCertificateManager sharedManager] verifyP12Certificate:p12Cert withProvisionProfile:profile];
            NSLog(@"[证书选择] 检查描述文件 %@ 是否匹配: %@", profile.certificateName ?: profile.filename, isMatching ? @"是" : @"否");
            if (isMatching) {
                [matchingProfiles addObject:profile];
            }
        }
        
        if (matchingProfiles.count == 0) {
            NSLog(@"[证书选择] 错误: 没有找到与证书匹配的描述文件");
            [ALToastView showToastWithText:@"没有找到与证书匹配的描述文件"];
            return;
        }
        
        if (matchingProfiles.count == 1) {
            // 只有一个匹配的描述文件，直接使用
            ZXCertificateModel *profile = matchingProfiles.firstObject;
            NSLog(@"[证书选择] 只有一个匹配的描述文件，直接使用: %@", profile.certificateName ?: profile.filename);
            
            // 调用签名方法
            NSLog(@"[证书选择] 调用performUploadWithP12:provisionProfile:andIpa:方法");
            [self performUploadWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
        } else {
            // 多个匹配的描述文件，显示选择器
            NSLog(@"[证书选择] 有多个匹配的描述文件 (%lu个)，显示选择器", (unsigned long)matchingProfiles.count);
            
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择描述文件"
                                                                                     message:@"请选择用于签名的描述文件"
                                                                              preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (ZXCertificateModel *profile in matchingProfiles) {
                NSString *profileName = profile.certificateName ?: profile.filename;
                UIAlertAction *action = [UIAlertAction actionWithTitle:profileName
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"[证书选择] 用户选择了描述文件: %@", profileName);
                    [self performUploadWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                }];
                [alertController addAction:action];
            }
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
            [alertController addAction:cancelAction];
            
            // 在iPad上需要设置弹出位置
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                alertController.popoverPresentationController.sourceView = self.view;
                alertController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
                alertController.popoverPresentationController.permittedArrowDirections = 0;
            }
            
            NSLog(@"[证书选择] 显示描述文件选择器");
            [self presentViewController:alertController animated:YES completion:nil];
        }
    } else {
        // 多个P12证书，显示选择器
        NSLog(@"[证书选择] 有多个P12证书 (%lu个)，显示选择器", (unsigned long)p12Certificates.count);
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择证书"
                                                                                 message:@"请选择用于签名的证书"
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
        
        for (ZXCertificateModel *p12Cert in p12Certificates) {
            // 查找匹配的描述文件
            NSMutableArray *matchingProfiles = [NSMutableArray array];
            
            for (ZXCertificateModel *profile in provisionProfiles) {
                if ([[ZXCertificateManager sharedManager] verifyP12Certificate:p12Cert withProvisionProfile:profile]) {
                    [matchingProfiles addObject:profile];
                }
            }
            
            // 只有有匹配的描述文件时才添加此证书选项
            if (matchingProfiles.count > 0) {
                NSString *certName = p12Cert.certificateName ?: p12Cert.filename;
                NSString *title = [NSString stringWithFormat:@"%@ (%lu个描述文件)", 
                                  certName,
                                  (unsigned long)matchingProfiles.count];
                
                UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    NSLog(@"[证书选择] 用户选择了证书: %@", certName);
                    
                    if (matchingProfiles.count == 1) {
                        // 只有一个匹配的描述文件，直接使用
                        ZXCertificateModel *profile = matchingProfiles.firstObject;
                        NSLog(@"[证书选择] 只有一个匹配的描述文件，直接使用: %@", profile.certificateName ?: profile.filename);
                        [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                    } else {
                        // 多个匹配的描述文件，显示选择器
                        NSLog(@"[证书选择] 有多个匹配的描述文件 (%lu个)，显示选择器", (unsigned long)matchingProfiles.count);
                        
                        UIAlertController *profileController = [UIAlertController alertControllerWithTitle:@"选择描述文件"
                                                                                                   message:@"请选择用于签名的描述文件"
                                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
                        
                        for (ZXCertificateModel *profile in matchingProfiles) {
                            NSString *profileName = profile.certificateName ?: profile.filename;
                            UIAlertAction *profileAction = [UIAlertAction actionWithTitle:profileName
                                                                                    style:UIAlertActionStyleDefault
                                                                                  handler:^(UIAlertAction * _Nonnull action) {
                                NSLog(@"[证书选择] 用户选择了描述文件: %@", profileName);
                                [self startSigningWithP12:p12Cert provisionProfile:profile andIpa:ipaModel];
                            }];
                            [profileController addAction:profileAction];
                        }
                        
                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
                        [profileController addAction:cancelAction];
                        
                        // 在iPad上需要设置弹出位置
                        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                            profileController.popoverPresentationController.sourceView = self.view;
                            profileController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
                            profileController.popoverPresentationController.permittedArrowDirections = 0;
                        }
                        
                        NSLog(@"[证书选择] 显示描述文件选择器");
                        [self presentViewController:profileController animated:YES completion:nil];
                    }
                }];
                [alertController addAction:action];
            }
        }
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        [alertController addAction:cancelAction];
        
        // 在iPad上需要设置弹出位置
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            alertController.popoverPresentationController.sourceView = self.view;
            alertController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
            alertController.popoverPresentationController.permittedArrowDirections = 0;
        }
        
        NSLog(@"[证书选择] 显示证书选择器");
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

// 执行上传操作
- (void)performUploadWithP12:(ZXCertificateModel *)p12Cert provisionProfile:(ZXCertificateModel *)profile andIpa:(ZXIpaModel *)ipaModel {
    NSLog(@"[上传] ========== 开始上传文件 ==========");
    NSLog(@"[上传] P12路径: %@", p12Cert.filepath);
    NSLog(@"[上传] 描述文件路径: %@", profile.filepath);
    NSLog(@"[上传] IPA路径: %@", ipaModel.localPath);
    
    // 获取证书密码
    NSString *p12Password = [[ZXCertificateManager sharedManager] passwordForP12Certificate:p12Cert];
    NSLog(@"[上传] P12密码: %@", p12Password ? @"已设置" : @"未设置");
    
    // 检查文件是否存在
    BOOL p12Exists = [[NSFileManager defaultManager] fileExistsAtPath:p12Cert.filepath];
    BOOL provisionExists = [[NSFileManager defaultManager] fileExistsAtPath:profile.filepath];
    BOOL ipaExists = [[NSFileManager defaultManager] fileExistsAtPath:ipaModel.localPath];
    
    NSLog(@"[上传] P12文件存在: %@", p12Exists ? @"是" : @"否");
    NSLog(@"[上传] 描述文件存在: %@", provisionExists ? @"是" : @"否");
    NSLog(@"[上传] IPA文件存在: %@", ipaExists ? @"是" : @"否");
    
    if (!p12Exists || !provisionExists || !ipaExists) {
        NSLog(@"[上传] 错误: 文件不存在，中止上传");
        [ALToastView showToastWithText:@"文件不存在，无法上传"];
        return;
    }
    
    // 显示加载指示器
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在上传文件...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 设置上传URL
    NSString *urlString = @"https://cloud.cloudmantoub.online/sign";
    NSLog(@"[上传] 上传URL: %@", urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    
    // 创建请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    // 增加超时时间
    [request setTimeoutInterval:600]; // 10分钟超时
    
    // 创建唯一边界字符串
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    NSLog(@"[上传] 设置请求边界: %@", boundary);
    
    // 创建请求体
    NSMutableData *body = [NSMutableData data];
    
    // 添加p12文件
    [self appendFileData:body 
                withName:@"p12" 
                fileName:@"certificate.p12" 
                filePath:p12Cert.filepath 
                boundary:boundary];
    
    // 添加描述文件
    [self appendFileData:body 
                withName:@"mobileprovision" 
                fileName:@"profile.mobileprovision" 
                filePath:profile.filepath 
                boundary:boundary];
    
    // 添加IPA文件
    [self appendFileData:body 
                withName:@"ipa" 
                fileName:@"app.ipa" 
                filePath:ipaModel.localPath 
                boundary:boundary];
    
    // 添加密码
    if (p12Password) {
        [self appendTextData:body 
                    withName:@"p12_password" 
                       value:p12Password 
                    boundary:boundary];
        NSLog(@"[上传] 已添加P12密码到表单");
    } else {
        NSLog(@"[上传] 警告: P12密码为空");
    }
    
    // 添加结束边界
    NSString *boundaryEnd = [NSString stringWithFormat:@"--%@--\r\n", boundary];
    [body appendData:[boundaryEnd dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"[上传] 表单数据总大小: %lu bytes", (unsigned long)body.length);
    
    // 设置请求体
    [request setHTTPBody:body];
    
    // 创建会话和任务
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 600; // 10分钟超时
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSLog(@"[上传] 开始上传任务");
    
    NSURLSessionDataTask *uploadTask = [session dataTaskWithRequest:request
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
            
            if (error) {
                NSLog(@"[上传] 上传错误: %@", error.localizedDescription);
                [ALToastView showToastWithText:[NSString stringWithFormat:@"上传失败: %@", error.localizedDescription]];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[上传] 上传完成，状态码: %ld", (long)httpResponse.statusCode);
            NSLog(@"[上传] 响应头: %@", httpResponse.allHeaderFields);
            
            if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[上传] 服务器响应: %@", responseString);
                
                // 尝试解析JSON
                NSError *jsonError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    NSLog(@"[上传] JSON解析错误: %@", jsonError.localizedDescription);
                    [ALToastView showToastWithText:@"签名请求已发送，但无法解析响应"];
                } else {
                    NSLog(@"[上传] JSON响应: %@", jsonResponse);
                    
                    // 根据响应显示不同消息并处理下载
                    if ([httpResponse statusCode] >= 200 && [httpResponse statusCode] < 300) {
                        // 尝试获取下载链接
                        NSString *installLink = jsonResponse[@"installLink"];
                        NSString *downloadUrl = jsonResponse[@"downloadUrl"] ?: jsonResponse[@"url"];
                        
                        if (downloadUrl) {
                            NSLog(@"[上传] 获取到下载链接: %@", downloadUrl);
                            [self downloadSignedIpa:downloadUrl withOriginalIpa:ipaModel installAfterDownload:YES];
                        } else if (installLink) {
                            NSLog(@"[上传] 获取到安装链接: %@", installLink);
                            // 保存安装链接到IPA模型中
                            ipaModel.installLink = installLink;
                            ipaModel.isSigned = YES;
                            ipaModel.signedTime = [self currentTimeString];
                            
                            // 保存更新后的IPA信息到数据库
                            [ipaModel zx_dbSave];
                            
                            // 显示成功消息
                            [ALToastView showToastWithText:@"签名成功，正在安装..."];
                            
                            // 直接调用安装方法
                            [self installIpaWithLink:installLink];
                        } else {
                            [ALToastView showToastWithText:@"签名请求发送成功，请等待签名完成"];
                        }
                    } else {
                        // 尝试获取错误消息
                        NSString *errorMessage = jsonResponse[@"error"] ?: jsonResponse[@"message"] ?: @"签名请求发送失败";
                        [ALToastView showToastWithText:errorMessage];
                    }
                }
            } else {
                NSLog(@"[上传] 没有响应数据");
                [ALToastView showToastWithText:@"签名请求已发送，但没有响应数据"];
            }
        });
    }];
    
    [uploadTask resume];
    NSLog(@"[上传] 上传任务已启动");
}

// 添加一个新方法，用于恢复可能丢失的IPA文件
- (void)recoverMissingIpaFiles {
    NSLog(@"[恢复] 开始检查并恢复可能丢失的IPA文件");
    
    // 获取Documents目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保ImportedIpa目录存在
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        [ZXFileManage creatDirWithPath:importedIpaPath];
        NSLog(@"[恢复] 创建ImportedIpa目录");
    }
    
    // 从数据库中获取所有IPA记录
    NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 0 OR isSigned IS NULL"];
    NSLog(@"[恢复] 从数据库中加载了%lu个IPA记录", (unsigned long)dbIpaModels.count);
    
    // 获取ImportedIpa目录中的所有文件
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *existingFiles = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
    
    if (error) {
        NSLog(@"[恢复] 读取ImportedIpa目录失败: %@", error.localizedDescription);
        return;
    }
    
    // 创建文件名到路径的映射
    NSMutableDictionary *fileNameToPath = [NSMutableDictionary dictionary];
    NSMutableDictionary *bundleIdToPath = [NSMutableDictionary dictionary]; // 新增：bundleId到路径的映射
    
    // 解析所有IPA文件，获取bundleId信息
    for (NSString *fileName in existingFiles) {
        if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:fileName];
            fileNameToPath[fileName] = fullPath;
            
            // 尝试解析IPA获取bundleId
            ZXIpaModel *tempModel = [self parseIpaFile:fullPath];
            if (tempModel && tempModel.bundleId) {
                bundleIdToPath[tempModel.bundleId] = fullPath;
                NSLog(@"[恢复] 解析到IPA文件 %@ 的bundleId: %@", fileName, tempModel.bundleId);
            }
        }
    }
    
    // 检查每个数据库记录
    int recoveredCount = 0;
    for (ZXIpaModel *ipaModel in dbIpaModels) {
        // 检查文件是否存在
        if (![ZXFileManage fileExistWithPath:ipaModel.localPath]) {
            NSLog(@"[恢复] 文件不存在: %@", ipaModel.localPath);
            
            // 获取文件名
            NSString *fileName = [ipaModel.localPath lastPathComponent];
            
            // 1. 首先检查ImportedIpa目录中是否有同名文件
            NSString *newPath = fileNameToPath[fileName];
            if (newPath) {
                NSLog(@"[恢复] 找到同名文件: %@", newPath);
                ipaModel.localPath = newPath;
                [ipaModel zx_dbSave];
                recoveredCount++;
                continue;
            }
            
            // 2. 然后检查是否有相同bundleId的文件
            NSString *bundleIdPath = bundleIdToPath[ipaModel.bundleId];
            if (bundleIdPath) {
                NSLog(@"[恢复] 找到相同bundleId的文件: %@", bundleIdPath);
                ipaModel.localPath = bundleIdPath;
                [ipaModel zx_dbSave];
                recoveredCount++;
                continue;
            }
            
            // 3. 最后尝试在ImportedIpa目录中查找类似名称的文件
            for (NSString *existingFileName in fileNameToPath.allKeys) {
                // 检查是否包含相同的bundleId或应用名称
                if ([existingFileName containsString:ipaModel.bundleId] || 
                    [existingFileName containsString:ipaModel.title] ||
                    [ipaModel.title containsString:existingFileName]) {
                    NSLog(@"[恢复] 找到类似文件: %@", existingFileName);
                    NSString *similarPath = fileNameToPath[existingFileName];
                    ipaModel.localPath = similarPath;
                    [ipaModel zx_dbSave];
                    recoveredCount++;
                    break;
                }
            }
        }
    }
    
    // 检查是否有ImportedIpa目录中的文件没有对应的数据库记录
    int addedCount = 0;
    for (NSString *fileName in existingFiles) {
        if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:fileName];
            
            // 检查是否已经在数据库中
            BOOL found = NO;
            for (ZXIpaModel *model in dbIpaModels) {
                if ([model.localPath isEqualToString:fullPath]) {
                    found = YES;
                    break;
                }
            }
            
            if (!found) {
                NSLog(@"[恢复] 发现未记录的IPA文件: %@，尝试解析并添加", fileName);
                
                // 解析IPA文件
                ZXIpaModel *newModel = [self parseIpaFile:fullPath];
                if (newModel) {
                    // 设置本地路径
                    newModel.localPath = fullPath;
                    
                    // 设置时间
                    if (!newModel.time) {
                        newModel.time = [self currentTimeString];
                    }
                    
                    // 生成唯一标识
                    if (!newModel.sign) {
                        NSString *orgSign = [NSString stringWithFormat:@"%@_%@_%@", 
                                            newModel.bundleId, 
                                            newModel.version, 
                                            [self currentTimeString]];
                        newModel.sign = [orgSign md5Str];
                    }
                    
                    // 保存到数据库
                    [self saveIpaInfoToDatabase:newModel];
                    addedCount++;
                }
            }
        }
    }
    
    NSLog(@"[恢复] 恢复完成，共恢复%d个文件，新增%d个文件", recoveredCount, addedCount);
}

// 修改从plist文件中提取IPA下载链接的方法
- (void)downloadPlistAndExtractIpaUrl:(NSString *)plistUrl withOriginalIpa:(ZXIpaModel *)originalIpa {
    NSLog(@"[下载] 开始下载plist文件: %@", plistUrl);
    
    // 显示加载指示器
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在获取签名后的IPA...";
    hud.mode = MBProgressHUDModeIndeterminate;
    
    // 创建下载任务
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:plistUrl] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 在主线程更新UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [hud hideAnimated:YES];
                NSLog(@"[下载] 下载plist失败: %@", error.localizedDescription);
                [ALToastView showToastWithText:@"获取签名后的IPA失败"];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[下载] 下载plist完成，状态码: %ld", (long)httpResponse.statusCode);
            
            if (data) {
                // 解析plist文件
                NSError *plistError = nil;
                NSDictionary *plistDict = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&plistError];
                
                if (plistError) {
                    [hud hideAnimated:YES];
                    NSLog(@"[下载] 解析plist失败: %@", plistError.localizedDescription);
                    [ALToastView showToastWithText:@"解析签名信息失败"];
                    return;
                }
                
                // 提取IPA下载链接
                NSString *ipaUrl = nil;
                
                // 打印整个plist内容以便调试
                NSLog(@"[下载] plist内容: %@", plistDict);
                
                // 尝试从items数组中提取
                id itemsObj = plistDict[@"items"];
                if ([itemsObj isKindOfClass:[NSArray class]]) {
                    NSArray *items = (NSArray *)itemsObj;
                    if (items.count > 0) {
                        id firstItem = items[0];
                        if ([firstItem isKindOfClass:[NSDictionary class]]) {
                            id assetsObj = [(NSDictionary *)firstItem objectForKey:@"assets"];
                            if ([assetsObj isKindOfClass:[NSArray class]]) {
                                NSArray *assets = (NSArray *)assetsObj;
                                for (id asset in assets) {
                                    if ([asset isKindOfClass:[NSDictionary class]]) {
                                        NSDictionary *assetDict = (NSDictionary *)asset;
                                        NSString *kind = assetDict[@"kind"];
                                        if ([kind isEqualToString:@"software-package"]) {
                                            ipaUrl = assetDict[@"url"];
                                            NSLog(@"[下载] 从plist中提取到IPA下载链接: %@", ipaUrl);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                if (ipaUrl) {
                    // 下载签名后的IPA
                    [hud hideAnimated:YES];
                    
                    // 直接安装IPA，不再下载
                    NSString *installUrl = [NSString stringWithFormat:@"itms-services://?action=download-manifest&url=%@", [plistUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
                    NSLog(@"[下载] 直接使用安装链接: %@", installUrl);
                    
                    // 保存安装链接到模型
                    originalIpa.installLink = installUrl;
                    originalIpa.isSigned = YES;
                    originalIpa.signedTime = [self currentTimeString];
                    [originalIpa zx_dbSave];
                    
                    // 显示成功消息并直接安装
                    [ALToastView showToastWithText:@"签名成功，正在安装..."];
                    [self installIpaWithLink:installUrl];
                } else {
                    [hud hideAnimated:YES];
                    NSLog(@"[下载] 无法从plist中提取IPA下载链接");
                    [ALToastView showToastWithText:@"无法获取签名后的IPA下载链接"];
                }
            } else {
                [hud hideAnimated:YES];
                [ALToastView showToastWithText:@"获取签名后的IPA失败，数据为空"];
            }
        });
    }];
    
    // 开始下载任务
    [task resume];
}

// 添加从历史记录导入IPA模型的方法
- (void)importIpaWithModel:(ZXIpaModel *)ipaModel {
    NSLog(@"[导入] 从历史记录导入IPA: %@", ipaModel.title);
    
    // 检查文件是否存在
    if (!ipaModel.localPath || ![ZXFileManage fileExistWithPath:ipaModel.localPath]) {
        [ALToastView showToastWithText:@"IPA文件不存在或已被删除"];
        return;
    }
    
    // 复制IPA文件到导入目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保导入目录存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:importPath]) {
        NSError *createDirError = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:importPath withIntermediateDirectories:YES attributes:nil error:&createDirError];
        
        if (createDirError) {
            NSLog(@"[导入] 创建ImportedIpa目录失败: %@", createDirError.localizedDescription);
            [ALToastView showToastWithText:@"创建导入目录失败"];
            return;
        }
    }
    
    // 生成新的文件名
    NSString *fileName = [ipaModel.localPath lastPathComponent];
    NSString *newPath = [importPath stringByAppendingPathComponent:fileName];
    
    // 如果目标文件已存在，先删除
    if ([[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
        NSError *removeError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:newPath error:&removeError];
        
        if (removeError) {
            NSLog(@"[导入] 删除已存在的文件失败: %@", removeError.localizedDescription);
            [ALToastView showToastWithText:@"导入失败，无法覆盖已存在的文件"];
            return;
        }
    }
    
    // 复制文件
    NSError *copyError = nil;
    [[NSFileManager defaultManager] copyItemAtPath:ipaModel.localPath toPath:newPath error:&copyError];
    
    if (copyError) {
        NSLog(@"[导入] 复制文件失败: %@", copyError.localizedDescription);
        [ALToastView showToastWithText:@"导入失败，无法复制文件"];
        return;
    }
    
    // 创建新的IPA模型
    ZXIpaModel *newIpaModel = [[ZXIpaModel alloc] init];
    newIpaModel.title = ipaModel.title;
    newIpaModel.version = ipaModel.version;
    newIpaModel.bundleId = ipaModel.bundleId;
    newIpaModel.iconUrl = ipaModel.iconUrl;
    newIpaModel.localPath = newPath;
    newIpaModel.time = [self currentTimeString];
    
    // 生成唯一标识
    NSString *uniqueString = [NSString stringWithFormat:@"%@_%@_imported_%@", newIpaModel.bundleId, newIpaModel.version, [self currentTimeString]];
    newIpaModel.sign = [uniqueString md5Str];
    
    // 添加到列表并刷新UI
    if (!self.ipaList) {
        self.ipaList = [NSMutableArray array];
    }
    [self.ipaList addObject:newIpaModel];
    [self.tableView reloadData];
    
    // 隐藏空视图
    [self hideEmptyView];
    
    [ALToastView showToastWithText:@"IPA导入成功"];
}

#pragma mark - 安装IPA
- (void)installIpaWithLink:(NSString *)installLink {
    if (!installLink || installLink.length == 0) {
        [ALToastView showToastWithText:@"安装链接无效"];
        return;
    }
    
    NSLog(@"[安装] 使用链接安装IPA: %@", installLink);
    
    // 打开安装链接
    NSURL *url = [NSURL URLWithString:installLink];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                NSLog(@"[安装] 成功打开安装链接");
                [ALToastView showToastWithText:@"安装中，请在设备上确认"];
            } else {
                NSLog(@"[安装] 无法打开安装链接");
                [ALToastView showToastWithText:@"无法打开安装链接"];
            }
        }];
    } else {
        NSLog(@"[安装] 设备不支持打开此URL");
        [ALToastView showToastWithText:@"设备不支持打开此URL"];
    }
}

@end
