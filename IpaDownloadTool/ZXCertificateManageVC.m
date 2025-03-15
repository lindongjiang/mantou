//
//  ZXCertificateManageVC.m
//  IpaDownloadTool
//
//  Created on 2024/7/13.
//  Copyright © 2024. All rights reserved.
//

#import "ZXCertificateManageVC.h"
#import "ZXCertificateManager.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface ZXCertificateManageVC () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) ZXCertificateManager *certificateManager;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *certificatePairs;
@property (nonatomic, strong) NSMutableDictionary *currentImportingPair;

@end

@implementation ZXCertificateManageVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"证书管理";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 初始化证书管理器
    self.certificateManager = [ZXCertificateManager sharedManager];
    self.certificatePairs = [NSMutableArray array];
    
    [self setupUI];
    [self loadCertificates];
}

- (void)setupUI {
    // 添加导入按钮
    UIBarButtonItem *importButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importCertificate)];
    self.navigationItem.rightBarButtonItem = importButton;
    
    // 创建tableView
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [UIView new]; // 去除空白cell的分割线
    [self.view addSubview:self.tableView];
    
    // 注册cell
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"CertificateCell"];
}

#pragma mark - 数据处理

- (void)loadCertificates {
    // 清空当前数据
    [self.certificatePairs removeAllObjects];
    
    // 获取所有证书
    NSArray<ZXCertificateModel *> *p12Certificates = [self.certificateManager allP12Certificates];
    NSArray<ZXCertificateModel *> *provisionProfiles = [self.certificateManager allProvisionProfiles];
    
    // 先添加已匹配的证书对
    for (ZXCertificateModel *p12Model in p12Certificates) {
        BOOL isMatched = NO;
        
        for (ZXCertificateModel *provisionModel in provisionProfiles) {
            if ([self.certificateManager verifyP12Certificate:p12Model withProvisionProfile:provisionModel]) {
                NSMutableDictionary *pair = [NSMutableDictionary dictionary];
                pair[@"p12"] = p12Model;
                pair[@"provision"] = provisionModel;
                pair[@"matched"] = @YES;
                [self.certificatePairs addObject:pair];
                isMatched = YES;
                break;
            }
        }
        
        // 如果没有匹配的描述文件，添加单独的p12
        if (!isMatched) {
            NSMutableDictionary *pair = [NSMutableDictionary dictionary];
            pair[@"p12"] = p12Model;
            pair[@"matched"] = @NO;
            [self.certificatePairs addObject:pair];
        }
    }
    
    // 添加未匹配的描述文件
    for (ZXCertificateModel *provisionModel in provisionProfiles) {
        BOOL isMatched = NO;
        
        for (NSMutableDictionary *pair in self.certificatePairs) {
            if (pair[@"provision"] == provisionModel) {
                isMatched = YES;
                break;
            }
        }
        
        // 如果没有匹配的p12，添加单独的描述文件
        if (!isMatched) {
            NSMutableDictionary *pair = [NSMutableDictionary dictionary];
            pair[@"provision"] = provisionModel;
            pair[@"matched"] = @NO;
            [self.certificatePairs addObject:pair];
        }
    }
    
    [self.tableView reloadData];
}

#pragma mark - 操作方法

- (void)importCertificate {
    // 重置当前导入状态
    self.currentImportingPair = [NSMutableDictionary dictionary];
    
    // 使用UIAlertController代替ActionSheet，避免iPad上的崩溃
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"导入证书"
                                                                             message:@"请选择要导入的证书类型"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *p12Action = [UIAlertAction actionWithTitle:@"导入P12证书"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        [self importP12Certificate];
    }];
    
    UIAlertAction *provisionAction = [UIAlertAction actionWithTitle:@"导入描述文件"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
        [self importProvisionProfile];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [alertController addThemeAction:p12Action];
    [alertController addThemeAction:provisionAction];
    [alertController addThemeAction:cancelAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)importP12Certificate {
    // 使用文档选择器导入p12证书
    NSArray *documentTypes = @[(NSString *)kUTTypeData];
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:documentTypes inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)importProvisionProfile {
    // 使用文档选择器导入mobileprovision证书
    NSArray *documentTypes = @[(NSString *)kUTTypeData];
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:documentTypes inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

// 验证p12证书密码
- (void)verifyP12Password:(NSString *)path completion:(void (^)(BOOL success, NSString *password))completion {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"请输入P12证书密码"
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"证书密码";
        textField.secureTextEntry = YES;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = alertController.textFields.firstObject.text;
        
        // 验证p12密码是否正确
        NSData *p12Data = [NSData dataWithContentsOfFile:path];
        NSDictionary *options = @{(id)kSecImportExportPassphrase: password};
        CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
        
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
        
        if (status == errSecSuccess) {
            if (items) {
                CFRelease(items);
            }
            completion(YES, password);
        } else {
            // 密码错误，重新提示
            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"密码错误"
                                                                                message:@"请输入正确的P12证书密码"
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self verifyP12Password:path completion:completion];
            }];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                completion(NO, nil);
            }];
            [errorAlert addThemeAction:okAction];
            [errorAlert addThemeAction:cancelAction];
            [self presentViewController:errorAlert animated:YES completion:nil];
            
            if (items) {
                CFRelease(items);
            }
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        completion(NO, nil);
    }];
    
    [alertController addThemeAction:confirmAction];
    [alertController addThemeAction:cancelAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

// 提示导入匹配的描述文件
- (void)promptForMatchingProvisionProfile:(ZXCertificateModel *)p12Model {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"导入描述文件"
                                                                             message:@"P12证书已成功导入，是否现在导入匹配的描述文件？"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *importAction = [UIAlertAction actionWithTitle:@"导入描述文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // 保存当前正在导入的p12证书
        self.currentImportingPair[@"p12"] = p12Model;
        [self importProvisionProfile];
    }];
    
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"稍后导入" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        // 重置当前导入状态
        self.currentImportingPair = [NSMutableDictionary dictionary];
        [self loadCertificates];
    }];
    
    [alertController addThemeAction:importAction];
    [alertController addThemeAction:laterAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = [urls firstObject];
    
    if (!url) return;
    
    // 判断文件类型
    NSString *fileExtension = [url.lastPathComponent.pathExtension lowercaseString];
    
    if ([fileExtension isEqualToString:@"p12"]) {
        // P12证书需要密码验证
        [self verifyP12Password:[url path] completion:^(BOOL success, NSString *password) {
            if (success) {
                NSData *certificateData = [NSData dataWithContentsOfURL:url];
                BOOL saveSuccess = [self.certificateManager saveP12Certificate:certificateData withFilename:url.lastPathComponent password:password];
                
                if (saveSuccess) {
                    // 获取保存的p12证书模型
                    NSArray<ZXCertificateModel *> *p12Certificates = [self.certificateManager allP12Certificates];
                    ZXCertificateModel *p12Model = nil;
                    
                    for (ZXCertificateModel *model in p12Certificates) {
                        if ([model.filename isEqualToString:url.lastPathComponent]) {
                            p12Model = model;
                            break;
                        }
                    }
                    
                    if (p12Model) {
                        // 提示导入匹配的描述文件
                        [self promptForMatchingProvisionProfile:p12Model];
                    } else {
                        [self showAlertWithTitle:@"导入成功" message:@"P12证书已成功导入"];
                        [self loadCertificates];
                    }
                } else {
                    [self showAlertWithTitle:@"导入失败" message:@"无法保存P12证书"];
                }
            }
        }];
    } else if ([fileExtension isEqualToString:@"mobileprovision"]) {
        // 导入mobileprovision文件
        NSData *profileData = [NSData dataWithContentsOfURL:url];
        BOOL saveSuccess = [self.certificateManager saveProvisionProfile:profileData withFilename:url.lastPathComponent];
        
        if (saveSuccess) {
            // 获取保存的描述文件模型
            NSArray<ZXCertificateModel *> *provisionProfiles = [self.certificateManager allProvisionProfiles];
            ZXCertificateModel *provisionModel = nil;
            
            for (ZXCertificateModel *model in provisionProfiles) {
                if ([model.filename isEqualToString:url.lastPathComponent]) {
                    provisionModel = model;
                    break;
                }
            }
            
            if (provisionModel) {
                // 如果当前正在导入p12对应的描述文件
                if (self.currentImportingPair[@"p12"]) {
                    ZXCertificateModel *p12Model = self.currentImportingPair[@"p12"];
                    
                    // 检查是否匹配
                    BOOL isMatching = [self.certificateManager verifyP12Certificate:p12Model withProvisionProfile:provisionModel];
                    
                    if (isMatching) {
                        [self showAlertWithTitle:@"导入成功" message:@"描述文件已成功导入，并与P12证书匹配成功！"];
                    } else {
                        [self showAlertWithTitle:@"导入成功" message:@"描述文件已成功导入，但与P12证书不匹配。"];
                    }
                    
                    // 重置当前导入状态
                    self.currentImportingPair = [NSMutableDictionary dictionary];
                } else {
                    [self showAlertWithTitle:@"导入成功" message:@"描述文件已成功导入"];
                }
                
                [self loadCertificates];
            } else {
                [self showAlertWithTitle:@"导入失败" message:@"无法解析描述文件"];
            }
        } else {
            [self showAlertWithTitle:@"导入失败" message:@"无法保存描述文件"];
        }
    } else {
        [self showAlertWithTitle:@"导入失败" message:@"不支持的文件类型"];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // 用户取消了操作
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.certificatePairs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CertificateCell" forIndexPath:indexPath];
    
    NSDictionary *pair = self.certificatePairs[indexPath.row];
    BOOL isMatched = [pair[@"matched"] boolValue];
    
    // 设置单元格样式
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    if (isMatched) {
        // 匹配的证书对
        ZXCertificateModel *p12Model = pair[@"p12"];
        ZXCertificateModel *provisionModel = pair[@"provision"];
        
        cell.textLabel.text = [NSString stringWithFormat:@"%@ (已匹配)", p12Model.certificateName ?: p12Model.filename];
        
        // 设置详细信息
        NSMutableString *detailText = [NSMutableString string];
        
        if (p12Model.teamID) {
            [detailText appendFormat:@"团队ID: %@", p12Model.teamID];
        }
        
        if (provisionModel.expirationDate) {
            if (detailText.length > 0) {
                [detailText appendString:@" | "];
            }
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd";
            NSString *expirationString = [formatter stringFromDate:provisionModel.expirationDate];
            [detailText appendFormat:@"过期时间: %@", expirationString];
            
            // 检查是否过期
            NSDate *now = [NSDate date];
            if ([now compare:provisionModel.expirationDate] == NSOrderedDescending) {
                cell.textLabel.textColor = [UIColor redColor]; // 已过期，显示红色
                [detailText appendString:@" (已过期)"];
            } else {
                cell.textLabel.textColor = [UIColor blackColor]; // 未过期，显示黑色
            }
        }
        
        cell.detailTextLabel.text = detailText.length > 0 ? detailText : nil;
    } else if (pair[@"p12"]) {
        // 只有p12证书
        ZXCertificateModel *p12Model = pair[@"p12"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ (缺少描述文件)", p12Model.certificateName ?: p12Model.filename];
        cell.textLabel.textColor = [UIColor orangeColor]; // 未匹配，显示橙色
    } else if (pair[@"provision"]) {
        // 只有描述文件
        ZXCertificateModel *provisionModel = pair[@"provision"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ (缺少P12证书)", provisionModel.certificateName ?: provisionModel.filename];
        cell.textLabel.textColor = [UIColor orangeColor]; // 未匹配，显示橙色
        
        // 显示过期时间
        if (provisionModel.expirationDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd";
            NSString *expirationString = [formatter stringFromDate:provisionModel.expirationDate];
            
            NSMutableString *detailText = [NSMutableString stringWithFormat:@"过期时间: %@", expirationString];
            
            // 检查是否过期
            NSDate *now = [NSDate date];
            if ([now compare:provisionModel.expirationDate] == NSOrderedDescending) {
                [detailText appendString:@" (已过期)"];
                cell.textLabel.textColor = [UIColor redColor]; // 已过期，显示红色
            }
            
            cell.detailTextLabel.text = detailText;
        }
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *pair = self.certificatePairs[indexPath.row];
        
        // 删除证书
        if (pair[@"p12"]) {
            [self.certificateManager deleteCertificate:pair[@"p12"]];
        }
        
        if (pair[@"provision"]) {
            [self.certificateManager deleteCertificate:pair[@"provision"]];
        }
        
        // 从数组中移除
        [self.certificatePairs removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *pair = self.certificatePairs[indexPath.row];
    BOOL isMatched = [pair[@"matched"] boolValue];
    
    NSString *title;
    NSMutableString *message = [NSMutableString string];
    
    if (isMatched) {
        // 匹配的证书对
        ZXCertificateModel *p12Model = pair[@"p12"];
        ZXCertificateModel *provisionModel = pair[@"provision"];
        
        title = @"证书信息";
        
        [message appendFormat:@"P12证书: %@\n", p12Model.certificateName ?: p12Model.filename];
        [message appendFormat:@"描述文件: %@\n", provisionModel.certificateName ?: provisionModel.filename];
        
        if (p12Model.teamID) {
            [message appendFormat:@"团队ID: %@\n", p12Model.teamID];
        }
        
        if (provisionModel.expirationDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            NSString *expirationString = [formatter stringFromDate:provisionModel.expirationDate];
            [message appendFormat:@"过期时间: %@", expirationString];
            
            // 检查是否过期
            NSDate *now = [NSDate date];
            if ([now compare:provisionModel.expirationDate] == NSOrderedDescending) {
                [message appendString:@" (已过期)"];
            }
        }
    } else if (pair[@"p12"]) {
        // 只有p12证书
        ZXCertificateModel *p12Model = pair[@"p12"];
        
        title = @"P12证书信息";
        
        [message appendFormat:@"文件名: %@\n", p12Model.filename];
        
        if (p12Model.certificateName) {
            [message appendFormat:@"名称: %@\n", p12Model.certificateName];
        }
        
        if (p12Model.teamID) {
            [message appendFormat:@"团队ID: %@\n", p12Model.teamID];
        }
        
        [message appendString:@"\n缺少匹配的描述文件，请导入匹配的描述文件。"];
    } else if (pair[@"provision"]) {
        // 只有描述文件
        ZXCertificateModel *provisionModel = pair[@"provision"];
        
        title = @"描述文件信息";
        
        [message appendFormat:@"文件名: %@\n", provisionModel.filename];
        
        if (provisionModel.certificateName) {
            [message appendFormat:@"名称: %@\n", provisionModel.certificateName];
        }
        
        if (provisionModel.teamID) {
            [message appendFormat:@"团队ID: %@\n", provisionModel.teamID];
        }
        
        if (provisionModel.expirationDate) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            NSString *expirationString = [formatter stringFromDate:provisionModel.expirationDate];
            [message appendFormat:@"过期时间: %@", expirationString];
            
            // 检查是否过期
            NSDate *now = [NSDate date];
            if ([now compare:provisionModel.expirationDate] == NSOrderedDescending) {
                [message appendString:@" (已过期)"];
            }
        }
        
        [message appendString:@"\n缺少匹配的P12证书，请导入匹配的P12证书。"];
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alertController addThemeAction:okAction];
    
    // 如果是未匹配的证书，添加导入匹配证书的选项
    if (!isMatched) {
        NSString *actionTitle;
        
        if (pair[@"p12"]) {
            actionTitle = @"导入匹配的描述文件";
        } else if (pair[@"provision"]) {
            actionTitle = @"导入匹配的P12证书";
        }
        
        if (actionTitle) {
            UIAlertAction *importAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                if (pair[@"p12"]) {
                    // 保存当前正在导入的p12证书
                    self.currentImportingPair[@"p12"] = pair[@"p12"];
                    [self importProvisionProfile];
                } else if (pair[@"provision"]) {
                    // 保存当前正在导入的描述文件
                    self.currentImportingPair[@"provision"] = pair[@"provision"];
                    [self importP12Certificate];
                }
            }];
            
            [alertController addThemeAction:importAction];
        }
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - 辅助方法

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alertController addThemeAction:okAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

@end 
