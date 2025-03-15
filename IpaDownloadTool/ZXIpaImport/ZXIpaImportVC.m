#import "ZXIpaImportVC.h"
#import "ZXFileManage.h"
#import "ZXIpaModel.h"
#import <objc/runtime.h>
#import "NSString+ZXMD5.h"
#import "SSZipArchive.h"

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
            BOOL securityAccessGranted = [url startAccessingSecurityScopedResource];
            
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
                    [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:&removeError];
                    if (removeError) {
                        NSLog(@"删除已存在文件失败: %@", removeError.localizedDescription);
                    }
                }
                
                // 直接读取文件数据并写入
                NSError *readError = nil;
                NSData *fileData = [NSData dataWithContentsOfURL:url options:0 error:&readError];
                
                if (readError || !fileData) {
                    NSLog(@"读取文件数据失败: %@", readError ? readError.localizedDescription : @"未知错误");
                    continue;
                }
                
                // 写入文件
                NSError *writeError = nil;
                BOOL writeSuccess = [fileData writeToFile:destinationPath options:NSDataWritingAtomic error:&writeError];
                
                if (!writeSuccess || writeError) {
                    NSLog(@"写入文件失败: %@", writeError ? writeError.localizedDescription : @"未知错误");
                    continue;
                }
                
                NSLog(@"成功导入文件到: %@", destinationPath);
                
                // 解析IPA文件
                ZXIpaModel *ipaModel = [self parseIpaFile:destinationPath];
                if (ipaModel) {
                    // 记录URL信息
                    ipaModel.downloadUrl = [url absoluteString];
                    
                    // 添加到列表
                    @synchronized (self.ipaList) {
                        [self.ipaList addObject:ipaModel];
                    }
                    
                    // 保存到数据库
                    [self saveIpaInfoToDatabase:ipaModel];
                    
                    NSLog(@"成功解析并保存IPA信息: %@", ipaModel.title);
                } else {
                    NSLog(@"解析IPA文件失败: %@", destinationPath);
                }
            } @catch (NSException *exception) {
                NSLog(@"处理文件时发生异常: %@", exception);
            } @finally {
                // 释放安全访问权限
                if (securityAccessGranted) {
                    [url stopAccessingSecurityScopedResource];
                }
            }
        }
        
        // 在主线程更新UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
            
            // 检查是否需要显示空视图
            if (self.ipaList.count == 0) {
                [self showEmptyView];
            } else {
                [self hideEmptyView];
            }
            
            [ALToastView showToastWithText:@"文件导入完成"];
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
    
    // 从数据库中加载所有IPA信息
    NSArray *dbIpaModels = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 0 OR isSigned IS NULL"];
    NSLog(@"[加载] 从数据库中加载了%lu个IPA记录", (unsigned long)dbIpaModels.count);
    
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
                                                          options:NSURLBookmarkResolutionWithSecurityScope
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
                
                BOOL accessGranted = [fileURL startAccessingSecurityScopedResource];
                
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
                                    if (fileSize > 1024 * 1024 * 1024) {
                                        sizeStr = [NSString stringWithFormat:@"%.2f GB", fileSize / 1024.0 / 1024.0 / 1024.0];
                                    } else if (fileSize > 1024 * 1024) {
                                        sizeStr = [NSString stringWithFormat:@"%.2f MB", fileSize / 1024.0 / 1024.0];
                                    } else if (fileSize > 1024) {
                                        sizeStr = [NSString stringWithFormat:@"%.2f KB", fileSize / 1024.0];
                                    } else {
                                        sizeStr = [NSString stringWithFormat:@"%lld B", fileSize];
                                    }
                                    
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
                    if (accessGranted) {
                        [fileURL stopAccessingSecurityScopedResource];
                    }
                }
            } else {
                NSLog(@"[加载] 未找到书签数据，从数据库中删除记录");
                [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
            }
        } else {
            // 处理复制到沙盒的IPA文件
            NSLog(@"[加载] 处理本地IPA文件: %@, 路径: %@", ipaModel.title, ipaModel.localPath);
            
            if ([ZXFileManage fileExistWithPath:ipaModel.localPath]) {
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
                        if (fileSize > 1024 * 1024 * 1024) {
                            sizeStr = [NSString stringWithFormat:@"%.2f GB", fileSize / 1024.0 / 1024.0 / 1024.0];
                        } else if (fileSize > 1024 * 1024) {
                            sizeStr = [NSString stringWithFormat:@"%.2f MB", fileSize / 1024.0 / 1024.0];
                        } else if (fileSize > 1024) {
                            sizeStr = [NSString stringWithFormat:@"%.2f KB", fileSize / 1024.0];
                        } else {
                            sizeStr = [NSString stringWithFormat:@"%lld B", fileSize];
                        }
                        
                        // 缓存文件大小
                        [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:fileSizeKey];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                    }
                }
                
                // 在自定义属性中存储文件大小字符串
                objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                [self.ipaList addObject:ipaModel];
            } else {
                NSLog(@"[加载] 文件不存在，从数据库中删除记录");
                [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
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
    
    // 获取文件哈希值作为缓存键
    NSString *fileName = [filePath lastPathComponent];
    NSString *fileHash = [self fileHashForPath:filePath];
    NSString *cacheKey = [NSString stringWithFormat:@"ipaCache_%@", fileHash];
    
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
    
    // 首次加载IPA文件
    [self initialLoadIpaFiles];
    
    // 注册通知，监听应用进入前台事件
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationWillEnterForeground) 
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
    
    // 检查是否需要刷新数据
    if ([self shouldRefreshData]) {
        NSLog(@"[生命周期] 检测到需要刷新数据");
        [self incrementalLoadIpaFiles];
    } else {
        NSLog(@"[生命周期] 无需刷新数据");
    }
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
- (void)applicationWillEnterForeground {
    // 应用从后台恢复时，检查是否需要刷新数据
    if ([self shouldRefreshData]) {
        NSLog(@"[通知] 应用进入前台，检测到需要刷新数据");
        [self incrementalLoadIpaFiles];
    }
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
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 获取应用沙盒目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *tmpPath = NSTemporaryDirectory();
    NSString *homePath = NSHomeDirectory();
    
    // 获取当前应用容器的路径
    NSString *containerPath = [homePath stringByDeletingLastPathComponent];
    
    NSLog(@"=== 应用沙盒目录信息 ===");
    NSLog(@"Home: %@", homePath);
    NSLog(@"Documents: %@", documentsPath);
    NSLog(@"Library: %@", libraryPath);
    NSLog(@"Temp: %@", tmpPath);
    NSLog(@"Container: %@", containerPath);
    
    // 创建并验证ImportedIpa目录
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:importedIpaPath]) {
        if ([fileManager createDirectoryAtPath:importedIpaPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"成功创建ImportedIpa目录: %@", importedIpaPath);
        } else {
            NSLog(@"创建ImportedIpa目录失败: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"ImportedIpa目录已存在: %@", importedIpaPath);
        
        // 列出目录中的文件
        NSArray *files = [fileManager contentsOfDirectoryAtPath:importedIpaPath error:&error];
        if (error) {
            NSLog(@"读取ImportedIpa目录失败: %@", error.localizedDescription);
        } else {
            NSLog(@"ImportedIpa目录中有%lu个文件", (unsigned long)files.count);
            for (NSString *file in files) {
                NSString *fullPath = [importedIpaPath stringByAppendingPathComponent:file];
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:&error];
                if (error) {
                    NSLog(@"获取文件属性失败: %@", error.localizedDescription);
                } else {
                    NSLog(@"文件: %@, 大小: %lld bytes", file, [attributes fileSize]);
                }
            }
        }
    }
    
    // 验证目录权限
    NSLog(@"验证目录权限：");
    NSData *testData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *testFilePath = [importedIpaPath stringByAppendingPathComponent:@"test.txt"];
    
    if ([testData writeToFile:testFilePath atomically:YES]) {
        NSLog(@"可以写入文件到ImportedIpa目录");
        [fileManager removeItemAtPath:testFilePath error:nil];
    } else {
        NSLog(@"无法写入文件到ImportedIpa目录");
    }
    
    NSLog(@"=== 目录验证完成 ===");
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
                                                           options:NSURLBookmarkResolutionWithSecurityScope
                                                     relativeToURL:nil
                                               bookmarkDataIsStale:&stale
                                                             error:&bookmarkError];
            
            if (!bookmarkError && resolvedURL) {
                fileURL = resolvedURL; // 使用解析后的URL
                securityAccessGranted = [fileURL startAccessingSecurityScopedResource];
                NSLog(@"成功获取安全访问权限: %@", securityAccessGranted ? @"是" : @"否");
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
        if (isExternalFile && securityAccessGranted) {
            [fileURL stopAccessingSecurityScopedResource];
        }
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
    
    // 设置自动布局约束
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 表格视图约束
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
        [self.tableView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.importButton.topAnchor constant:-10],
        
        // 导入按钮约束
        [self.importButton.heightAnchor constraintEqualToConstant:50],
        [self.importButton.widthAnchor constraintEqualToConstant:200],
        [self.importButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.importButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
    
    NSLog(@"UI设置完成，表格视图和导入按钮已创建");
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
        
        // 添加上传选项
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"上传到服务器"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // 调用上传方法
            [self uploadIpaFile:ipaModel];
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
        
        [self presentViewController:actionSheet animated:YES completion:nil];
    }
}

// 删除IPA文件
- (void)deleteIpaFile:(ZXIpaModel *)ipaModel atIndexPath:(NSIndexPath *)indexPath {
    BOOL isExternalFile = [ipaModel.bundleId hasPrefix:@"direct."];
    
    // 只删除数据库记录，不删除原始文件
    if (isExternalFile) {
        // 删除书签
        NSString *bookmarkKey = [NSString stringWithFormat:@"bookmark_%@", ipaModel.bundleId];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:bookmarkKey];
    } else {
        // 对于复制到沙盒的文件，可以删除实际文件
        if ([ZXFileManage fileExistWithPath:ipaModel.localPath]) {
            [ZXFileManage delFileWithPath:ipaModel.localPath];
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
    [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
    
    // 更新UI
    [self.ipaList removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    
    // 检查是否需要显示空视图
    if (self.ipaList.count == 0) {
        [self showEmptyView];
    }
}

#pragma mark - 保存IPA信息到数据库
- (void)saveIpaInfoToDatabase:(ZXIpaModel *)ipaModel {
    if (!ipaModel) {
        return;
    }
    
    NSLog(@"保存IPA信息到数据库: %@", ipaModel.title);
    
    // 1. 检查是否已存在相同的IPA
    NSArray *sameArr = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
    if (sameArr.count) {
        // 如果已存在，则删除旧记录
        NSLog(@"数据库中已存在相同Bundle ID的记录，删除旧记录: %@", ipaModel.bundleId);
        [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"bundleId='%@'", ipaModel.bundleId]];
    }
    
    // 2. 确保时间字段有值
    NSDate *date = [NSDate date];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    // 如果时间未设置，则使用当前时间
    if (!ipaModel.time || [ipaModel.time isEqualToString:@"未知日期"]) {
        ipaModel.time = [format stringFromDate:date];
    }
    
    // 3. 生成唯一标识
    if (!ipaModel.sign) {
        NSString *orgSign = [NSString stringWithFormat:@"%@%@%@", 
                              ipaModel.bundleId, 
                              ipaModel.version, 
                              ipaModel.localPath];
        ipaModel.sign = [orgSign md5Str];
    }
    
    // 4. 检查是否有图标路径
    if (ipaModel.iconUrl) {
        NSLog(@"保存图标路径到数据库: %@", ipaModel.iconUrl);
    } else {
        NSLog(@"没有找到图标路径");
    }
    
    // 5. 将IPA信息保存到数据库
    BOOL saveResult = [ipaModel zx_dbSave];
    
    if (saveResult) {
        NSLog(@"成功保存IPA信息到数据库");
    } else {
        NSLog(@"保存IPA信息到数据库失败");
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
