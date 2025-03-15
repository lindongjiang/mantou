//
//  ZXIpaImportVC.m
//  IpaDownloadTool
//
//  Created on 2023/3/15.
//  Copyright © 2023. All rights reserved.
//

#import "ZXIpaImportVC.h"
#import "ZXIpaModel.h"
#import "TCMobileProvision.h"
#import "ZXFileManage.h"
#import <objc/runtime.h>
#import "ALToastView.h"
#import "SSZipArchive.h"

@interface ZXIpaImportVC () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<ZXIpaModel *> *ipaList;
@property (nonatomic, strong) UIButton *importButton;

@end

@implementation ZXIpaImportVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self loadLocalIpaFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadLocalIpaFiles];
}

#pragma mark - UI设置
- (void)setupUI {
    self.title = @"导入IPA";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 创建表格视图
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 100;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];
    
    // 设置表格视图约束
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
        [self.tableView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-80]
    ]];
    
    // 创建导入按钮
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importButton setTitle:@"导入IPA文件" forState:UIControlStateNormal];
    self.importButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    [self.importButton setTintColor:[UIColor whiteColor]];
    [self.importButton setBackgroundColor:MainColor];
    self.importButton.layer.cornerRadius = 25;
    [self.importButton addTarget:self action:@selector(importIpaFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importButton];
    
    // 设置导入按钮约束
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.importButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.importButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.importButton.widthAnchor constraintEqualToConstant:200],
        [self.importButton.heightAnchor constraintEqualToConstant:50]
    ]];
    
    // 注册单元格
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"IpaCell"];
}

#pragma mark - 加载本地IPA文件
- (void)loadLocalIpaFiles {
    if (!self.ipaList) {
        self.ipaList = [NSMutableArray array];
    } else {
        [self.ipaList removeAllObjects];
    }
    
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保导入IPA的目录存在
    if (![ZXFileManage fileExistWithPath:importedIpaPath]) {
        [ZXFileManage creatDirWithPathComponent:importedIpaPath];
    }
    
    NSArray *fileList = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:importedIpaPath error:nil];
    for (NSString *fileName in fileList) {
        if ([fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSString *filePath = [importedIpaPath stringByAppendingPathComponent:fileName];
            ZXIpaModel *ipaModel = [self parseIpaFile:filePath];
            if (ipaModel) {
                [self.ipaList addObject:ipaModel];
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
    // 获取文件大小
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    NSNumber *fileSizeNumber = fileAttributes[NSFileSize];
    long long fileSize = [fileSizeNumber longLongValue];
    
    // 创建基本的IPA模型
    ZXIpaModel *ipaModel = [[ZXIpaModel alloc] init];
    
    // 从文件名提取应用名称
    NSString *fileName = [filePath lastPathComponent];
    NSString *appName = [fileName stringByDeletingPathExtension];
    
    // 设置基本信息
    ipaModel.title = appName;
    ipaModel.version = @"未知"; // 默认值，稍后会尝试从Info.plist获取
    ipaModel.bundleId = [NSString stringWithFormat:@"unknown.%@", [[NSUUID UUID] UUIDString]]; // 默认值
    ipaModel.localPath = filePath;
    ipaModel.time = [self formattedDateFromFileAttributes:fileAttributes];
    
    // 设置文件大小字符串
    NSString *sizeStr;
    if (fileSize > 1024 * 1024 * 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f GB", fileSize / 1024.0 / 1024.0 / 1024.0];
    } else if (fileSize > 1024 * 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f MB", fileSize / 1024.0 / 1024.0];
    } else if (fileSize > 1024) {
        sizeStr = [NSString stringWithFormat:@"%.2f KB", fileSize / 1024.0];
    } else {
        sizeStr = [NSString stringWithFormat:@"%lld B", fileSize];
    }
    
    // 在自定义属性中存储文件大小字符串
    objc_setAssociatedObject(ipaModel, "fileSize", sizeStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 使用SSZipArchive解压IPA文件以提取信息
    if (NSClassFromString(@"SSZipArchive")) {
        NSLog(@"开始解析IPA文件: %@", filePath);
        
        // 创建临时解压目录
        NSString *tempUnzipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:tempUnzipPath withIntermediateDirectories:YES attributes:nil error:nil];
        
        // 解压IPA文件
        BOOL unzipSuccess = [SSZipArchive unzipFileAtPath:filePath toDestination:tempUnzipPath];
        
        if (unzipSuccess) {
            NSLog(@"成功解压IPA文件到: %@", tempUnzipPath);
            
            // 查找Payload目录
            NSString *payloadPath = [tempUnzipPath stringByAppendingPathComponent:@"Payload"];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:payloadPath]) {
                // 查找.app目录
                NSArray *appDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
                NSString *appDirName = nil;
                
                for (NSString *dirName in appDirs) {
                    if ([dirName.pathExtension isEqualToString:@"app"]) {
                        appDirName = dirName;
                        break;
                    }
                }
                
                if (appDirName) {
                    NSString *appPath = [payloadPath stringByAppendingPathComponent:appDirName];
                    NSLog(@"找到应用目录: %@", appPath);
                    
                    // 读取Info.plist文件
                    NSString *infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    
                    if ([[NSFileManager defaultManager] fileExistsAtPath:infoPlistPath]) {
                        NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
                        
                        if (infoPlist) {
                            // 获取应用名称
                            NSString *bundleDisplayName = infoPlist[@"CFBundleDisplayName"];
                            NSString *bundleName = infoPlist[@"CFBundleName"];
                            
                            if (bundleDisplayName && bundleDisplayName.length > 0) {
                                ipaModel.title = bundleDisplayName;
                            } else if (bundleName && bundleName.length > 0) {
                                ipaModel.title = bundleName;
                            }
                            
                            // 获取Bundle ID
                            NSString *bundleID = infoPlist[@"CFBundleIdentifier"];
                            if (bundleID && bundleID.length > 0) {
                                ipaModel.bundleId = bundleID;
                            }
                            
                            // 获取版本号
                            NSString *bundleVersion = infoPlist[@"CFBundleShortVersionString"];
                            if (bundleVersion && bundleVersion.length > 0) {
                                ipaModel.version = bundleVersion;
                            }
                            
                            NSLog(@"从Info.plist获取到应用信息 - 名称: %@, Bundle ID: %@, 版本: %@", 
                                  ipaModel.title, ipaModel.bundleId, ipaModel.version);
                            
                            // 查找应用图标
                            NSMutableArray *possibleIconPaths = [NSMutableArray array];
                            
                            // 方法1: 从CFBundleIcons获取
                            id primaryIconDict = infoPlist[@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
                            if ([primaryIconDict isKindOfClass:[NSDictionary class]]) {
                                NSArray *iconFiles = primaryIconDict[@"CFBundleIconFiles"];
                                if (iconFiles.count > 0) {
                                    for (NSString *iconFile in iconFiles) {
                                        [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:iconFile]];
                                        [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", iconFile]]];
                                    }
                                }
                            }
                            
                            // 方法2: 从CFBundleIconFiles获取
                            NSArray *iconFiles = infoPlist[@"CFBundleIconFiles"];
                            if (iconFiles.count > 0) {
                                for (NSString *iconFile in iconFiles) {
                                    [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:iconFile]];
                                    [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", iconFile]]];
                                }
                            }
                            
                            // 方法3: 查找常见图标名称
                            NSArray *commonIconNames = @[
                                @"AppIcon60x60@2x.png", @"AppIcon60x60@3x.png",
                                @"Icon.png", @"Icon@2x.png",
                                @"Icon-60.png", @"Icon-60@2x.png", @"Icon-60@3x.png"
                            ];
                            
                            for (NSString *iconName in commonIconNames) {
                                [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:iconName]];
                            }
                            
                            // 方法4: 直接在APP目录下查找符合AppIcon*.png的文件
                            NSArray *appFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil];
                            for (NSString *fileName in appFiles) {
                                if ([fileName hasPrefix:@"AppIcon"] && [fileName hasSuffix:@".png"]) {
                                    [possibleIconPaths addObject:[appPath stringByAppendingPathComponent:fileName]];
                                }
                            }
                            
                            // 创建AppIcons目录
                            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                            NSString *iconsDir = [documentsPath stringByAppendingPathComponent:@"AppIcons"];
                            
                            [[NSFileManager defaultManager] createDirectoryAtPath:iconsDir 
                                                      withIntermediateDirectories:YES 
                                                                       attributes:nil 
                                                                            error:nil];
                            
                            // 为图标生成唯一文件名
                            NSString *iconFileName = [NSString stringWithFormat:@"%@_%@.png", 
                                                     ipaModel.bundleId ?: [[NSUUID UUID] UUIDString], 
                                                     @([NSDate date].timeIntervalSince1970)];
                            NSString *destIconPath = [iconsDir stringByAppendingPathComponent:iconFileName];
                            
                            // 尝试所有可能的图标路径
                            BOOL iconFound = NO;
                            
                            for (NSString *iconPath in possibleIconPaths) {
                                if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
                                    NSLog(@"找到图标文件: %@", iconPath);
                                    
                                    NSError *copyError = nil;
                                    [[NSFileManager defaultManager] copyItemAtPath:iconPath toPath:destIconPath error:&copyError];
                                    
                                    if (!copyError) {
                                        ipaModel.iconUrl = destIconPath;
                                        NSLog(@"成功复制应用图标到: %@", destIconPath);
                                        iconFound = YES;
                                        break;
                                    }
                                }
                            }
                            
                            if (!iconFound) {
                                NSLog(@"无法找到有效的图标文件");
                            }
                        } else {
                            NSLog(@"无法读取Info.plist文件内容");
                        }
                    } else {
                        NSLog(@"找不到Info.plist文件");
                    }
                } else {
                    NSLog(@"在Payload目录中找不到.app目录");
                }
            } else {
                NSLog(@"找不到Payload目录");
            }
            
            // 清理临时目录
            [[NSFileManager defaultManager] removeItemAtPath:tempUnzipPath error:nil];
            
        } else {
            NSLog(@"解压IPA文件失败");
        }
    } else {
        NSLog(@"SSZipArchive库不可用，无法解压IPA文件");
    }
    
    return ipaModel;
}

- (NSString *)formattedDateFromFileAttributes:(NSDictionary *)attributes {
    NSDate *creationDate = attributes[NSFileCreationDate];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [formatter stringFromDate:creationDate];
}

#pragma mark - 导入IPA文件
- (void)importIpaFile {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.itunes.ipa"] inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:nil];
    
    // 获取Documents目录路径
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    
    // 创建ImportedIpa目录的完整路径
    NSString *importedIpaPath = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    
    // 确保ImportedIpa目录存在
    NSError *createDirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:importedIpaPath 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&createDirError];
    
    if (createDirError) {
        NSLog(@"创建导入目录失败: %@", createDirError.localizedDescription);
        [ALToastView showToastWithText:@"创建导入目录失败"];
        return;
    }
    
    NSLog(@"导入目录路径: %@", importedIpaPath);
    
    // 在主线程显示加载指示器
    dispatch_async(dispatch_get_main_queue(), ^{
        [ALToastView showToastWithText:@"正在导入文件..."];
    });
    
    // 在后台线程处理文件
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL importSuccess = NO;
        
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
                
                // 创建一个简单的文件名（避免特殊字符）
                NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
                NSString *simpleFileName = [NSString stringWithFormat:@"ipa_%@.ipa", timestamp];
                NSString *destinationPath = [importedIpaPath stringByAppendingPathComponent:simpleFileName];
                
                NSLog(@"使用简单文件名: %@", simpleFileName);
                NSLog(@"目标路径: %@", destinationPath);
                
                // 如果目标文件已存在，先删除
                if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
                    NSError *removeError = nil;
                    [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:&removeError];
                    if (removeError) {
                        NSLog(@"删除已存在文件失败: %@", removeError.localizedDescription);
                    }
                }
                
                // 直接读取文件数据
                NSError *readError = nil;
                NSData *fileData = [NSData dataWithContentsOfURL:url options:0 error:&readError];
                
                if (readError || !fileData) {
                    NSLog(@"读取文件数据失败: %@", readError ? readError.localizedDescription : @"未知错误");
                    continue;
                }
                
                NSLog(@"成功读取文件数据，大小: %lu 字节", (unsigned long)fileData.length);
                
                // 写入文件
                NSError *writeError = nil;
                BOOL writeSuccess = [fileData writeToFile:destinationPath options:NSDataWritingAtomic error:&writeError];
                
                if (!writeSuccess || writeError) {
                    NSLog(@"写入文件失败: %@", writeError ? writeError.localizedDescription : @"未知错误");
                    continue;
                }
                
                NSLog(@"成功导入文件到: %@", destinationPath);
                importSuccess = YES;
                
                // 解析IPA文件并保存原始文件名
                ZXIpaModel *ipaModel = [self parseIpaFile:destinationPath];
                if (ipaModel) {
                    // 保存原始文件名
                    ipaModel.title = [fileName stringByDeletingPathExtension];
                    ipaModel.downloadUrl = [url absoluteString];
                    
                    // 保存到数据库或其他操作
                    NSLog(@"成功解析IPA文件: %@", ipaModel.title);
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
            if (importSuccess) {
                [ALToastView showToastWithText:@"文件导入完成"];
            } else {
                [ALToastView showToastWithText:@"文件导入失败"];
            }
            
            // 重新加载IPA文件列表
            [self loadLocalIpaFiles];
        });
    });
}

#pragma mark - 空视图处理
- (void)showEmptyView {
    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = @"暂无已导入的IPA文件";
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.textColor = [UIColor grayColor];
    emptyLabel.tag = 100;
    [self.view addSubview:emptyLabel];
    
    emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor]
    ]];
}

- (void)hideEmptyView {
    UIView *emptyLabel = [self.view viewWithTag:100];
    [emptyLabel removeFromSuperview];
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
    
    // 设置应用图标
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 12;
    iconView.layer.masksToBounds = YES;
    
    if (ipaModel.iconUrl) {
        iconView.image = [UIImage imageWithContentsOfFile:ipaModel.iconUrl];
    } else {
        // 使用默认图标
        iconView.image = [UIImage imageNamed:@"default_app_icon"];
    }
    
    [cardView addSubview:iconView];
    
    // 设置应用名称
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = ipaModel.title ?: @"未知应用";
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [cardView addSubview:titleLabel];
    
    // 设置应用包ID
    UILabel *bundleIdLabel = [[UILabel alloc] init];
    bundleIdLabel.text = ipaModel.bundleId ?: @"未知包ID";
    bundleIdLabel.font = [UIFont systemFontOfSize:12];
    bundleIdLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:bundleIdLabel];
    
    // 设置版本号
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = [NSString stringWithFormat:@"版本: %@", ipaModel.version ?: @"未知"];
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:versionLabel];
    
    // 设置文件大小
    UILabel *sizeLabel = [[UILabel alloc] init];
    NSString *sizeStr = objc_getAssociatedObject(ipaModel, "fileSize");
    sizeLabel.text = [NSString stringWithFormat:@"大小: %@", sizeStr ?: @"未知"];
    sizeLabel.font = [UIFont systemFontOfSize:12];
    sizeLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:sizeLabel];
    
    // 设置导入时间
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.text = [NSString stringWithFormat:@"导入时间: %@", ipaModel.time ?: @"未知"];
    timeLabel.font = [UIFont systemFontOfSize:12];
    timeLabel.textColor = [UIColor darkGrayColor];
    [cardView addSubview:timeLabel];
    
    // 设置布局约束
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bundleIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        // 图标约束
        [iconView.leftAnchor constraintEqualToAnchor:cardView.leftAnchor constant:12],
        [iconView.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:60],
        [iconView.heightAnchor constraintEqualToConstant:60],
        
        // 标题约束
        [titleLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:12],
        [titleLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:12],
        [titleLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-12],
        
        // Bundle ID约束
        [bundleIdLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [bundleIdLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:12],
        [bundleIdLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-12],
        
        // 版本约束
        [versionLabel.topAnchor constraintEqualToAnchor:bundleIdLabel.bottomAnchor constant:4],
        [versionLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:12],
        
        // 大小约束
        [sizeLabel.topAnchor constraintEqualToAnchor:bundleIdLabel.bottomAnchor constant:4],
        [sizeLabel.leftAnchor constraintEqualToAnchor:versionLabel.rightAnchor constant:12],
        
        // 时间约束
        [timeLabel.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:4],
        [timeLabel.leftAnchor constraintEqualToAnchor:iconView.rightAnchor constant:12],
        [timeLabel.rightAnchor constraintEqualToAnchor:cardView.rightAnchor constant:-12],
        [timeLabel.bottomAnchor constraintLessThanOrEqualToAnchor:cardView.bottomAnchor constant:-12]
    ]];
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    
    return cell;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZXIpaModel *ipaModel = self.ipaList[indexPath.row];
    // 分享IPA文件
    [[ZXFileManage shareInstance] shareFileWithPath:ipaModel.localPath];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        ZXIpaModel *ipaModel = self.ipaList[indexPath.row];
        
        // 删除文件
        [ZXFileManage delFileWithPath:ipaModel.localPath];
        
        // 更新数据源
        [self.ipaList removeObjectAtIndex:indexPath.row];
        
        // 更新表格
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        
        // 检查是否需要显示空视图
        if (self.ipaList.count == 0) {
            [self showEmptyView];
        }
    }
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

@end 