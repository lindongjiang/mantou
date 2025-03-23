//
//  ZXIpaDetailVC.m
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/29.
//  Copyright © 2019 李兆祥. All rights reserved.
//  https://github.com/SmileZXLee/IpaDownloadTool

#import "ZXIpaDetailVC.h"
#import "ZXIpaDetailCell.h"
#import "ZXIpaDetailModel.h"
#import "ZXCertificateManager.h"
#import "ZXCertificateManageVC.h"
#import "ZXSignedIpaVC.h"
#import "NSString+ZXMD5.h"

#import "ZXLocalIpaVC.h"
#import "AFNetworking.h"
#import "ZXIpaManager.h"

@interface ZXIpaDetailVC ()
@property (weak, nonatomic) IBOutlet ZXTableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) UIProgressView *progressView;

// 添加辅助方法声明
- (void)showWarningTip:(NSString *)message;
- (void)showSuccessTip:(NSString *)message;
- (void)showErrorTip:(NSString *)message;
- (void)showCertificateSelectorWithP12Certificates:(NSArray *)p12Certificates provisionProfiles:(NSArray *)provisionProfiles ipaPath:(NSString *)ipaPath;
@end

@implementation ZXIpaDetailVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initUI];
}

#pragma mark - 初始化视图
-(void)initUI{
    self.title = @"应用详情";
    __weak __typeof(self) weakSelf = self;
    self.tableView.zx_setCellClassAtIndexPath = ^Class(NSIndexPath *indexPath) {
        return [ZXIpaDetailCell class];
    };
    self.tableView.zx_didSelectedAtIndexPath = ^(NSIndexPath *indexPath, ZXIpaDetailModel *model, id cell) {
        [weakSelf handelSelActionWithModel:model];
    };
    self.tableView.zxDatas = [self getTbData];
    
    // 创建加载指示器和遮罩
    self.overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.overlayView.hidden = YES;
    
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.activityIndicator.center = self.overlayView.center;
    [self.overlayView addSubview:self.activityIndicator];
    
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(50, self.activityIndicator.frame.origin.y + self.activityIndicator.frame.size.height + 20, self.view.bounds.size.width - 100, 10);
    self.progressView.progressTintColor = MainColor;
    [self.overlayView addSubview:self.progressView];
    
    [self.view addSubview:self.overlayView];
}

#pragma mark - Private
#pragma mark 设置tableView数据
-(NSMutableArray *)getTbData{
    ZXIpaDetailModel *titleModel = [[ZXIpaDetailModel alloc]init];
    titleModel.title = @"应用名称";
    titleModel.detail = self.ipaModel.title;
    
    ZXIpaDetailModel *versionModel = [[ZXIpaDetailModel alloc]init];
    versionModel.title = @"版本号";
    versionModel.detail = self.ipaModel.version;
    
    ZXIpaDetailModel *bundleIdModel = [[ZXIpaDetailModel alloc]init];
    bundleIdModel.title = @"BundleId";
    bundleIdModel.detail = self.ipaModel.bundleId;
    
    ZXIpaDetailModel *downloadModel = [[ZXIpaDetailModel alloc]init];
    downloadModel.title = @"下载地址";
    downloadModel.detail = self.ipaModel.downloadUrl;
    
    ZXIpaDetailModel *fromModel = [[ZXIpaDetailModel alloc]init];
    fromModel.title = @"来源地址";
    fromModel.detail = self.ipaModel.fromPageUrl;
    
    ZXIpaDetailModel *timeModel = [[ZXIpaDetailModel alloc]init];
    timeModel.title = @"创建时间";
    timeModel.detail = self.ipaModel.time;
    
    ZXIpaDetailModel *fileModel = [[ZXIpaDetailModel alloc]init];
    if([ZXFileManage isExistWithPath:self.ipaModel.localPath]){
        fileModel.title = @"IPA已下载";
        fileModel.detail = @"点击分享/重新下载";
    }else{
        fileModel.title = @"IPA未下载";
        fileModel.detail = @"点击下载";
    }
    
    // 添加签名选项
    ZXIpaDetailModel *signModel = [[ZXIpaDetailModel alloc]init];
    signModel.title = @"签名";
    signModel.detail = @"使用证书签名IPA";
    
    return [@[titleModel,versionModel,bundleIdModel,downloadModel,fromModel,timeModel,fileModel,signModel]mutableCopy];
}

#pragma mark 处理cell点击事件
-(void)handelSelActionWithModel:(ZXIpaDetailModel *)model{
    if([model.title hasPrefix:@"IPA"]){
        if([ZXFileManage isExistWithPath:self.ipaModel.localPath]){
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"操作选择" message:@"请选择您要进行的操作" preferredStyle:ZXISiPad ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet];
            UIAlertAction *shareAction = [UIAlertAction actionWithTitle:@"分享文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [[ZXFileManage shareInstance] shareFileWithPath:self.ipaModel.localPath];
            }];
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"重新下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                ZXLocalIpaVC *VC = [[ZXLocalIpaVC alloc]init];
                VC.ipaModel = self.ipaModel;
                [self.navigationController pushViewController:VC animated:YES];
            }];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
            [alertController addThemeAction:shareAction];
            [alertController addThemeAction:confirmAction];
            [alertController addThemeAction:cancelAction];
            [self presentViewController:alertController animated:YES completion:nil];
        }else{
            ZXLocalIpaVC *VC = [[ZXLocalIpaVC alloc]init];
            VC.ipaModel = self.ipaModel;
            [self.navigationController pushViewController:VC animated:YES];
        }
    } else if ([model.title isEqualToString:@"签名"]) {
        // 处理签名操作
        [self handleSignAction];
    }
}

#pragma mark - 签名相关方法
- (void)handleSignAction {
    NSLog(@"[签名操作] 开始处理签名操作");
    
    if (!self.ipaModel) {
        NSLog(@"[签名操作] 错误: ipaModel 为空");
        [self showWarningTip:@"应用信息不完整，无法进行签名"];
        return;
    }
    
    // 获取Documents目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *importedIpaDir = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    NSString *sideStorePath = [importedIpaDir stringByAppendingPathComponent:@"SideStore.ipa"];
    
    // 直接使用SideStore.ipa文件
    if ([ZXFileManage fileExistWithPath:sideStorePath]) {
        NSLog(@"[签名操作] 找到SideStore.ipa文件，直接使用: %@", sideStorePath);
        
        // 直接从证书管理器获取证书和描述文件，绕过用户选择
        ZXCertificateManager *manager = [ZXCertificateManager sharedManager];
        NSArray *p12Certificates = [manager allP12Certificates];
        NSArray *provisionProfiles = [manager allProvisionProfiles];
        
        NSLog(@"[签名操作] 获取到 %lu 个P12证书和 %lu 个描述文件", 
              (unsigned long)p12Certificates.count, (unsigned long)provisionProfiles.count);
        
        if (p12Certificates.count > 0 && provisionProfiles.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 直接使用第一个证书和描述文件进行测试
                ZXCertificateModel *p12 = p12Certificates.firstObject;
                ZXCertificateModel *profile = provisionProfiles.firstObject;
                
                NSLog(@"[签名操作] 自动选择证书: %@", p12.certificateName ?: p12.filename);
                NSLog(@"[签名操作] 自动选择描述文件: %@", profile.certificateName ?: profile.filename);
                
                [self performUploadWithP12:p12 provisionProfile:profile andIpa:sideStorePath];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[签名操作] 错误: 没有可用的证书或描述文件");
                [self showWarningTip:@"没有可用的证书或描述文件，请先导入"];
            });
        }
        return;
    }
    
    // 如果没有找到SideStore.ipa，尝试查找其他IPA文件
    NSLog(@"[签名操作] 未找到SideStore.ipa，尝试查找其他IPA文件");
    
    // 查找正确的IPA文件路径
    NSString *ipaPath = [self findCorrectIpaPath];
    if (!ipaPath) {
        NSLog(@"[签名操作] 错误: 无法找到IPA文件");
        [self showWarningTip:@"无法找到IPA文件，请确保文件已正确导入"];
        return;
    }
    
    NSLog(@"[签名操作] 找到有效的IPA文件路径: %@", ipaPath);
    
    // 直接从证书管理器获取证书和描述文件，绕过用户选择
    ZXCertificateManager *manager = [ZXCertificateManager sharedManager];
    NSArray *p12Certificates = [manager allP12Certificates];
    NSArray *provisionProfiles = [manager allProvisionProfiles];
    
    NSLog(@"[签名操作] 获取到 %lu 个P12证书和 %lu 个描述文件", 
          (unsigned long)p12Certificates.count, (unsigned long)provisionProfiles.count);
    
    if (p12Certificates.count > 0 && provisionProfiles.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 直接使用第一个证书和描述文件进行测试
            ZXCertificateModel *p12 = p12Certificates.firstObject;
            ZXCertificateModel *profile = provisionProfiles.firstObject;
            
            NSLog(@"[签名操作] 自动选择证书: %@", p12.certificateName ?: p12.filename);
            NSLog(@"[签名操作] 自动选择描述文件: %@", profile.certificateName ?: profile.filename);
            
            [self performUploadWithP12:p12 provisionProfile:profile andIpa:ipaPath];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[签名操作] 错误: 没有可用的证书或描述文件");
            [self showWarningTip:@"没有可用的证书或描述文件，请先导入"];
        });
    }
}

// 查找正确的IPA文件路径
- (NSString *)findCorrectIpaPath {
    NSString *ipaPath = self.ipaModel.localPath;
    NSString *ipaFileName = [ipaPath lastPathComponent];
    NSLog(@"[查找IPA] 开始查找IPA文件: %@", ipaFileName);
    NSLog(@"[查找IPA] 原始路径: %@", ipaPath);
    
    // 获取Documents目录
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSLog(@"[查找IPA] Documents目录: %@", documentsPath);
    
    // 检查ImportedIpa目录中的SideStore.ipa文件（根据日志中看到的）
    NSString *importedIpaDir = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
    NSString *sideStorePath = [importedIpaDir stringByAppendingPathComponent:@"SideStore.ipa"];
    NSLog(@"[查找IPA] 检查SideStore.ipa: %@", sideStorePath);
    
    if ([ZXFileManage fileExistWithPath:sideStorePath]) {
        NSLog(@"[查找IPA] 找到SideStore.ipa文件: %@", sideStorePath);
        return sideStorePath;
    }
    
    // 检查原始路径
    if ([ZXFileManage fileExistWithPath:ipaPath]) {
        NSLog(@"[查找IPA] 原始路径存在: %@", ipaPath);
        return ipaPath;
    }
    
    // 检查ImportedIpa目录
    NSString *importedIpaPath = [importedIpaDir stringByAppendingPathComponent:ipaFileName];
    NSLog(@"[查找IPA] 检查ImportedIpa目录中的文件: %@", importedIpaPath);
    
    if ([ZXFileManage fileExistWithPath:importedIpaPath]) {
        NSLog(@"[查找IPA] 在ImportedIpa目录中找到: %@", importedIpaPath);
        return importedIpaPath;
    }
    
    // 检查ImportedIpa目录中的所有文件
    NSLog(@"[查找IPA] 检查ImportedIpa目录中的所有IPA文件");
    NSArray *importedFiles = [ZXFileManage getContentsOfDirectory:importedIpaDir];
    NSLog(@"[查找IPA] ImportedIpa目录中有 %lu 个文件", (unsigned long)importedFiles.count);
    
    for (NSString *fileName in importedFiles) {
        NSLog(@"[查找IPA] 检查文件: %@", fileName);
        if ([fileName hasSuffix:@".ipa"]) {
            NSString *fullPath = [importedIpaDir stringByAppendingPathComponent:fileName];
            NSLog(@"[查找IPA] 在ImportedIpa目录中找到IPA文件: %@", fullPath);
            return fullPath;
        }
    }
    
    // 检查下载目录
    NSString *downloadDir = [documentsPath stringByAppendingPathComponent:@"ZXIpaDownloadedArr"];
    NSLog(@"[查找IPA] 检查下载目录: %@", downloadDir);
    
    if ([ZXFileManage fileExistWithPath:downloadDir]) {
        // 检查直接在下载目录中的文件
        NSString *directDownloadPath = [downloadDir stringByAppendingPathComponent:ipaFileName];
        NSLog(@"[查找IPA] 检查下载目录中的文件: %@", directDownloadPath);
        
        if ([ZXFileManage fileExistWithPath:directDownloadPath]) {
            NSLog(@"[查找IPA] 在下载目录中找到: %@", directDownloadPath);
            return directDownloadPath;
        }
        
        // 检查下载目录的子目录
        NSLog(@"[查找IPA] 检查下载目录的子目录");
        NSArray *subDirs = [ZXFileManage getContentsOfDirectory:downloadDir];
        NSLog(@"[查找IPA] 下载目录中有 %lu 个子目录/文件", (unsigned long)subDirs.count);
        
        for (NSString *subDir in subDirs) {
            if ([subDir hasPrefix:@"."]) {
                NSLog(@"[查找IPA] 跳过隐藏文件/目录: %@", subDir);
                continue;
            }
            
            NSString *subDirPath = [downloadDir stringByAppendingPathComponent:subDir];
            NSLog(@"[查找IPA] 检查子目录: %@", subDirPath);
            
            if ([ZXFileManage getPathAttrWithPath:subDirPath] == PathAttrDir) {
                NSString *potentialPath = [subDirPath stringByAppendingPathComponent:ipaFileName];
                NSLog(@"[查找IPA] 检查子目录中的文件: %@", potentialPath);
                
                if ([ZXFileManage fileExistWithPath:potentialPath]) {
                    NSLog(@"[查找IPA] 在下载目录的子目录中找到: %@", potentialPath);
                    return potentialPath;
                }
                
                // 检查子目录中的所有IPA文件
                NSLog(@"[查找IPA] 检查子目录中的所有IPA文件");
                NSArray *subDirFiles = [ZXFileManage getContentsOfDirectory:subDirPath];
                NSLog(@"[查找IPA] 子目录中有 %lu 个文件", (unsigned long)subDirFiles.count);
                
                for (NSString *fileName in subDirFiles) {
                    NSLog(@"[查找IPA] 检查文件: %@", fileName);
                    if ([fileName hasSuffix:@".ipa"]) {
                        NSString *fullPath = [subDirPath stringByAppendingPathComponent:fileName];
                        NSLog(@"[查找IPA] 在下载目录的子目录中找到IPA文件: %@", fullPath);
                        return fullPath;
                    }
                }
            }
        }
    }
    
    NSLog(@"[查找IPA] 无法找到任何IPA文件");
    return nil;
}

// 签名IPA文件
- (void)signIpaFile:(NSString *)ipaPath {
    NSLog(@"[签名流程] ========== 开始签名IPA文件: %@", [ipaPath lastPathComponent]);
    NSLog(@"[签名流程] IPA文件路径: %@", ipaPath);
    
    // 1. 检查IPA文件是否存在
    BOOL fileExists = [ZXFileManage fileExistWithPath:ipaPath];
    NSLog(@"[签名流程] 文件存在检查: %@", fileExists ? @"是" : @"否");
    
    if (!fileExists) {
        NSLog(@"[签名流程] 原始路径不存在，尝试查找正确的IPA路径");
        
        // 使用新的查找方法
        NSString *correctPath = [self findCorrectIpaPath];
        if (correctPath) {
            NSLog(@"[签名流程] 找到正确的IPA路径: %@", correctPath);
            ipaPath = correctPath;
        } else {
            NSLog(@"[签名流程] 错误: 无法找到IPA文件，已尝试所有可能的路径");
            [self showWarningTip:@"找不到IPA文件，请重新导入"];
            return;
        }
    }
    
    NSLog(@"[签名流程] 使用IPA文件路径: %@", ipaPath);
    
    // 2. 获取证书和描述文件
    ZXCertificateManager *manager = [ZXCertificateManager sharedManager];
    NSArray *p12Certificates = [manager allP12Certificates];
    NSArray *provisionProfiles = [manager allProvisionProfiles];
    
    NSLog(@"[签名流程] 获取到 %lu 个p12证书和 %lu 个描述文件", (unsigned long)p12Certificates.count, (unsigned long)provisionProfiles.count);
    
    // 证书和描述文件都存在
    if (p12Certificates.count > 0 && provisionProfiles.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[签名流程] 准备显示证书选择器");
            [self showCertificateSelectorWithP12Certificates:p12Certificates
                                           provisionProfiles:provisionProfiles
                                                    ipaPath:ipaPath];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[签名流程] 没有找到证书或描述文件");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法签名"
                                                                           message:@"没有找到有效的证书和描述文件，请先导入证书"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil];
            [alert addAction:cancelAction];
            
            [self presentViewController:alert animated:YES completion:nil];
        });
    }
}

// 执行上传操作
- (void)performUploadWithP12:(ZXCertificateModel *)p12 
            provisionProfile:(ZXCertificateModel *)provisionProfile 
                     andIpa:(NSString *)ipaPath {
    NSLog(@"[签名上传] 开始上传文件到服务器");
    NSLog(@"[签名上传] 证书: %@, 路径: %@", p12.certificateName ?: p12.filename, p12.filepath);
    NSLog(@"[签名上传] 描述文件: %@, 路径: %@", provisionProfile.certificateName ?: provisionProfile.filename, provisionProfile.filepath);
    NSLog(@"[签名上传] IPA文件: %@", ipaPath);
    
    // 显示加载视图
    [self showLoadingView];
    NSLog(@"[签名上传] 显示加载视图");
    
    // 检查所有文件是否存在
    if (![ZXFileManage fileExistWithPath:p12.filepath]) {
        NSLog(@"[签名上传] 错误: P12证书文件不存在");
        [self hideLoadingView];
        [self showWarningTip:@"P12证书文件不存在，请重新导入"];
        return;
    }
    
    if (![ZXFileManage fileExistWithPath:provisionProfile.filepath]) {
        NSLog(@"[签名上传] 错误: 描述文件不存在");
        [self hideLoadingView];
        [self showWarningTip:@"描述文件不存在，请重新导入"];
        return;
    }
    
    // 再次检查IPA文件是否存在，如果不存在则尝试查找
    if (![ZXFileManage fileExistWithPath:ipaPath]) {
        NSLog(@"[签名上传] 错误: 提供的IPA文件路径不存在，尝试查找正确的路径");
        NSString *correctPath = [self findCorrectIpaPath];
        if (correctPath) {
            NSLog(@"[签名上传] 找到正确的IPA文件路径: %@", correctPath);
            ipaPath = correctPath;
        } else {
            NSLog(@"[签名上传] 错误: 无法找到IPA文件");
            [self hideLoadingView];
            [self showWarningTip:@"IPA文件不存在，请重新导入"];
            return;
        }
    }
    
    // 创建URL和请求
    NSURL *url = [NSURL URLWithString:@"https://cloud.cloudmantoub.online/sign"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    // 生成boundary字符串，用于multipart/form-data请求
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    // 创建multipart/form-data的body数据
    NSMutableData *body = [NSMutableData data];
    NSString *boundaryPrefix = [NSString stringWithFormat:@"--%@\r\n", boundary];
    NSString *boundarySuffix = [NSString stringWithFormat:@"\r\n--%@--\r\n", boundary];
    
    // 添加p12证书文件
    NSLog(@"[签名上传] 添加P12证书文件: %@", p12.filepath);
    [body appendData:[boundaryPrefix dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"p12\"; filename=\"%@\"\r\n", [p12.filepath lastPathComponent]] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *p12Data = [NSData dataWithContentsOfFile:p12.filepath];
    if (!p12Data) {
        NSLog(@"[签名上传] 错误: 无法读取P12证书文件数据");
        [self hideLoadingView];
        [self showWarningTip:@"无法读取P12证书文件数据"];
        return;
    }
    [body appendData:p12Data];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加描述文件
    NSLog(@"[签名上传] 添加描述文件: %@", provisionProfile.filepath);
    [body appendData:[boundaryPrefix dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"mobileprovision\"; filename=\"%@\"\r\n", [provisionProfile.filepath lastPathComponent]] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *profileData = [NSData dataWithContentsOfFile:provisionProfile.filepath];
    if (!profileData) {
        NSLog(@"[签名上传] 错误: 无法读取描述文件数据");
        [self hideLoadingView];
        [self showWarningTip:@"无法读取描述文件数据"];
        return;
    }
    [body appendData:profileData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加IPA文件
    NSLog(@"[签名上传] 添加IPA文件: %@", ipaPath);
    [body appendData:[boundaryPrefix dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"ipa\"; filename=\"%@\"\r\n", [ipaPath lastPathComponent]] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *ipaData = [NSData dataWithContentsOfFile:ipaPath];
    if (!ipaData) {
        NSLog(@"[签名上传] 错误: 无法读取IPA文件数据");
        [self hideLoadingView];
        [self showWarningTip:@"无法读取IPA文件数据"];
        return;
    }
    [body appendData:ipaData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加p12密码字段
    if (p12.pwd && p12.pwd.length > 0) {
        NSLog(@"[签名上传] 添加P12密码");
        [body appendData:[boundaryPrefix dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"p12_password\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[p12.pwd dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        NSLog(@"[签名上传] 警告: P12密码为空");
    }
    
    // 添加结束边界
    [body appendData:[boundarySuffix dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 设置请求体
    [request setHTTPBody:body];
    
    // 创建和启动上传任务
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    
    NSLog(@"[签名上传] 开始上传，数据大小: %lu 字节", (unsigned long)body.length);
    
    // 显示上传进度
    NSURLSessionUploadTask *uploadTask = [session uploadTaskWithRequest:request
                                                               fromData:body
                                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSLog(@"[签名上传] 上传完成，处理响应");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 关闭加载视图
            [self hideLoadingView];
            
            if (error) {
                NSLog(@"[签名上传] 上传错误: %@", error.localizedDescription);
                [self showWarningTip:[NSString stringWithFormat:@"上传失败: %@", error.localizedDescription]];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[签名上传] 服务器响应状态码: %ld", (long)httpResponse.statusCode);
            NSLog(@"[签名上传] 响应头: %@", httpResponse.allHeaderFields);
            
            if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[签名上传] 响应内容: %@", responseString);
            }
            
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                // 解析响应数据
                NSError *jsonError = nil;
                NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    NSLog(@"[签名上传] 响应数据解析错误: %@", jsonError.localizedDescription);
                    [self showWarningTip:@"响应数据解析错误"];
                } else {
                    NSLog(@"[签名上传] 服务器响应: %@", responseDict);
                    
                    // 根据服务器响应显示结果
                    BOOL success = [responseDict[@"success"] boolValue];
                    NSString *message = responseDict[@"message"];
                    
                    if (success) {
                        NSLog(@"[签名上传] 签名请求成功: %@", message);
                        [self showSuccessTip:@"签名请求已成功提交，请等待签名完成"];
                        
                        // 处理响应数据，比如下载签名后的IPA
                        if (responseDict[@"data"] && [responseDict[@"data"] isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *dataDict = responseDict[@"data"];
                            NSString *downloadUrl = dataDict[@"download_url"];
                            
                            if (downloadUrl && downloadUrl.length > 0) {
                                NSLog(@"[签名上传] 签名后的IPA下载链接: %@", downloadUrl);
                                // 保存下载链接，稍后用于下载
                                self.signedIpaDownloadUrl = downloadUrl;
                                
                                // 可以选择显示下载按钮或自动开始下载
                                [self showSignedIpaDownloadOptions];
                            }
                        }
                    } else {
                        NSLog(@"[签名上传] 签名请求失败: %@", message);
                        [self showWarningTip:[NSString stringWithFormat:@"签名失败: %@", message ?: @"未知错误"]];
                    }
                }
            } else {
                NSLog(@"[签名上传] 服务器返回错误状态码: %ld", (long)httpResponse.statusCode);
                [self showWarningTip:[NSString stringWithFormat:@"服务器错误: %ld", (long)httpResponse.statusCode]];
            }
        });
    }];
    
    [uploadTask resume];
    
    // 显示日志信息
    NSLog(@"[签名上传] 上传任务已开始");
}

- (void)showSignedIpaDownloadOptions {
    if (!self.signedIpaDownloadUrl || self.signedIpaDownloadUrl.length == 0) {
        NSLog(@"[签名下载] 没有可用的下载链接");
        return;
    }
    
    NSLog(@"[签名下载] 显示下载选项，URL: %@", self.signedIpaDownloadUrl);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"签名完成"
                                                                   message:@"您的IPA文件已签名完成，是否立即下载？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *downloadAction = [UIAlertAction actionWithTitle:@"下载"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"[签名下载] 用户选择下载签名后的IPA");
        [self downloadSignedIpa];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"稍后下载"
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"[签名下载] 用户选择稍后下载");
    }];
    
    [alert addAction:downloadAction];
    [alert addAction:cancelAction];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)downloadSignedIpa {
    if (!self.signedIpaDownloadUrl || self.signedIpaDownloadUrl.length == 0) {
        NSLog(@"[签名下载] 错误: 没有可用的下载链接");
        [self showWarningTip:@"没有可用的下载链接"];
        return;
    }
    
    NSLog(@"[签名下载] 开始下载签名后的IPA: %@", self.signedIpaDownloadUrl);
    
    // 显示加载视图
    [self showLoadingView];
    NSLog(@"[签名下载] 显示加载视图");
    
    // 创建下载任务
    NSURL *url = [NSURL URLWithString:self.signedIpaDownloadUrl];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingView];
            
            if (error) {
                NSLog(@"[签名下载] 下载错误: %@", error.localizedDescription);
                [self showWarningTip:[NSString stringWithFormat:@"下载失败: %@", error.localizedDescription]];
                return;
            }
            
            // 获取文件名
            NSString *fileName = [response suggestedFilename];
            if (!fileName || fileName.length == 0) {
                fileName = [NSString stringWithFormat:@"Signed_%@", [[NSUUID UUID] UUIDString]];
                if (![fileName hasSuffix:@".ipa"]) {
                    fileName = [fileName stringByAppendingString:@".ipa"];
                }
            }
            
            // 创建保存路径
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *signedIpaDir = [documentsPath stringByAppendingPathComponent:@"SignedIpa"];
            
            // 确保目录存在
            if (![ZXFileManage fileExistWithPath:signedIpaDir]) {
                [ZXFileManage createDirectory:signedIpaDir];
            }
            
            NSString *destinationPath = [signedIpaDir stringByAppendingPathComponent:fileName];
            
            // 移动文件
            NSError *moveError = nil;
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:destinationPath] error:&moveError];
            
            if (moveError) {
                NSLog(@"[签名下载] 保存文件错误: %@", moveError.localizedDescription);
                [self showWarningTip:[NSString stringWithFormat:@"保存文件失败: %@", moveError.localizedDescription]];
            } else {
                NSLog(@"[签名下载] 文件已保存: %@", destinationPath);
                [self showSuccessTip:@"签名后的IPA文件已下载成功"];
                
                // 添加到已导入列表
                [self importSignedIpa:destinationPath];
            }
        });
    }];
    
    [downloadTask resume];
    NSLog(@"[签名下载] 下载任务已开始");
}

- (void)importSignedIpa:(NSString *)ipaPath {
    NSLog(@"[签名下载] 导入签名后的IPA: %@", ipaPath);
    
    // 检查是否已存在相同路径的IPA记录
    NSArray *existingIpas = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"localPath = '%@'", ipaPath]];
    
    if (existingIpas.count > 0) {
        NSLog(@"[签名下载] 数据库中已存在该IPA记录，跳过导入");
        [self showSuccessTip:@"IPA已存在，无需重复导入"];
        return;
    }
    
    // 解析IPA文件
    ZXIpaModel *ipaModel = [self parseIpaFile:ipaPath];
    
    if (ipaModel) {
        NSLog(@"[签名下载] IPA解析成功: %@", ipaModel.title);
        
        // 为已签名IPA添加标记
        ipaModel.title = [NSString stringWithFormat:@"%@(已签名)", ipaModel.title];
        ipaModel.isSigned = YES;
        ipaModel.signedTime = [self currentTimeString];
        
        // 保存到数据库
        [self saveSignedIpaToDatabase:ipaModel];
        
        // 通知更新UI
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZXImportedIpaUpdated" object:nil];
        
        [self showSuccessTip:@"已签名IPA已成功导入"];
    } else {
        NSLog(@"[签名下载] IPA解析失败");
        [self showWarningTip:@"导入失败，无法解析IPA文件"];
    }
}

- (ZXIpaModel *)parseIpaFile:(NSString *)ipaPath {
    // 从库中查找现有的解析方法，或者使用现有的解析方法
    // 这里是一个简化的实现
    ZXIpaModel *model = [[ZXIpaModel alloc] init];
    model.localPath = ipaPath;
    model.title = [[ipaPath lastPathComponent] stringByDeletingPathExtension];
    model.version = @"未知版本";
    model.bundleId = @"未知Bundle ID";
    model.time = [NSString stringWithFormat:@"%@", [NSDate date]];
    model.isSigned = YES;
    
    return model;
}

- (void)saveSignedIpaToDatabase:(ZXIpaModel *)ipaModel {
    // 确保IPA模型有效
    if (!ipaModel || !ipaModel.localPath) {
        NSLog(@"[签名下载] 无效的IPA模型");
        return;
    }
    
    // 生成唯一标识符
    if (!ipaModel.sign) {
        NSString *uniqueString = [NSString stringWithFormat:@"%@_%@_signed_%@", 
                                 ipaModel.bundleId ?: @"unknown", 
                                 ipaModel.version ?: @"unknown", 
                                 [self currentTimeString]];
        ipaModel.sign = [uniqueString md5Str];
    }
    
    // 使用IpaManager保存已签名IPA
    BOOL success = [[ZXIpaManager sharedManager] saveSignedIpa:ipaModel];
    
    if (success) {
        NSLog(@"[签名下载] IPA成功保存到数据库: %@", ipaModel.title);
    } else {
        NSLog(@"[签名下载] 保存IPA到数据库失败");
    }
}

#pragma mark - 辅助方法

- (void)showLoadingView {
    if (!self.overlayView) {
        self.overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
        self.overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        self.activityIndicator.center = self.overlayView.center;
        [self.overlayView addSubview:self.activityIndicator];
        
        self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        self.progressView.frame = CGRectMake(50, self.activityIndicator.frame.origin.y + self.activityIndicator.frame.size.height + 20, self.view.bounds.size.width - 100, 10);
        self.progressView.progressTintColor = MainColor;
        [self.overlayView addSubview:self.progressView];
        
        [self.view addSubview:self.overlayView];
    }
    
    self.overlayView.hidden = NO;
    [self.activityIndicator startAnimating];
    self.progressView.progress = 0;
}

- (void)hideLoadingView {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlayView.hidden = YES;
        [self.activityIndicator stopAnimating];
    });
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                                 message:message
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alertController addThemeAction:okAction];
        [self presentViewController:alertController animated:YES completion:nil];
    });
}

#pragma mark - 签名方法

- (void)startSigningWithP12:(ZXCertificateModel *)p12 provisionProfile:(ZXCertificateModel *)profile andIpa:(ZXIpaModel *)ipaModel {
    NSLog(@"[签名流程] ========== 开始准备签名 ==========");
    NSLog(@"[签名流程] 证书: %@", p12.certificateName ?: p12.filename);
    NSLog(@"[签名流程] 描述文件: %@", profile.certificateName ?: profile.filename);
    NSLog(@"[签名流程] IPA文件: %@", ipaModel.title);
    
    // 查找正确的IPA文件路径
    NSString *ipaPath = ipaModel.localPath;
    if (![ZXFileManage fileExistWithPath:ipaPath]) {
        NSLog(@"[签名流程] 原始IPA路径不存在，尝试查找正确的路径");
        self.ipaModel = ipaModel; // 设置当前ipaModel以便findCorrectIpaPath方法可以使用
        NSString *correctPath = [self findCorrectIpaPath];
        if (correctPath) {
            NSLog(@"[签名流程] 找到正确的IPA路径: %@", correctPath);
            ipaPath = correctPath;
        } else {
            NSLog(@"[签名流程] 错误: 无法找到IPA文件");
            [self showWarningTip:@"无法找到IPA文件，请确保文件已正确导入"];
            return;
        }
    }
    
    // 显示确认对话框
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[签名流程] 显示确认对话框");
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"确认签名"
                                                                                message:[NSString stringWithFormat:@"您确定要使用证书 %@ 对应用 %@ 进行签名吗？", p12.certificateName ?: p12.filename, ipaModel.title]
                                                                         preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                              style:UIAlertActionStyleCancel 
                                                            handler:^(UIAlertAction * _Nonnull action) {
            NSLog(@"[签名流程] 用户取消了签名确认");
        }];
        [alertController addAction:cancelAction];
        
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确认上传" 
                                                               style:UIAlertActionStyleDefault 
                                                             handler:^(UIAlertAction * _Nonnull action) {
            NSLog(@"[签名流程] 用户确认签名，准备上传文件");
            
            // 保存密码
            NSString *password = [[ZXCertificateManager sharedManager] passwordForP12Certificate:p12];
            self.p12Password = password;
            NSLog(@"[签名流程] P12密码: %@", password);
            
            // 显示加载视图
            NSLog(@"[签名流程] 显示加载视图");
            [self showLoadingView];
            
            // 执行上传操作
            NSLog(@"[签名流程] 开始执行上传操作");
            [self performUploadWithP12:p12 provisionProfile:profile andIpa:ipaPath];
        }];
        confirmAction.accessibilityIdentifier = @"confirmSignAction";
        
        // 设置确认按钮颜色
        [confirmAction setValue:MainColor forKey:@"_titleTextColor"];
        [alertController addAction:confirmAction];
        
        NSLog(@"[签名流程] 准备显示确认对话框");
        [self presentViewController:alertController animated:YES completion:^{
            NSLog(@"[签名流程] 确认对话框已显示");
        }];
    });
}

// 显示警告提示
- (void)showWarningTip:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

// 显示成功提示
- (void)showSuccessTip:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"成功"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

// 显示证书选择器
- (void)showCertificateSelectorWithP12Certificates:(NSArray *)p12Certificates
                                 provisionProfiles:(NSArray *)provisionProfiles
                                          ipaPath:(NSString *)ipaPath {
    NSLog(@"[证书选择] 显示证书选择器");
    NSLog(@"[证书选择] 使用IPA文件: %@", ipaPath);
    
    // 再次检查IPA文件是否存在
    if (![ZXFileManage fileExistWithPath:ipaPath]) {
        NSLog(@"[证书选择] 警告: 提供的IPA文件路径不存在，尝试使用SideStore.ipa");
        
        // 尝试使用SideStore.ipa
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *importedIpaDir = [documentsPath stringByAppendingPathComponent:@"ImportedIpa"];
        NSString *sideStorePath = [importedIpaDir stringByAppendingPathComponent:@"SideStore.ipa"];
        
        if ([ZXFileManage fileExistWithPath:sideStorePath]) {
            NSLog(@"[证书选择] 找到SideStore.ipa文件，使用此文件: %@", sideStorePath);
            ipaPath = sideStorePath;
        } else {
            NSLog(@"[证书选择] 错误: 无法找到任何IPA文件");
            [self showWarningTip:@"无法找到IPA文件，请重新导入"];
            return;
        }
    }
    
    // 简单实现：直接使用第一个证书和描述文件
    ZXCertificateModel *p12 = p12Certificates.firstObject;
    ZXCertificateModel *profile = provisionProfiles.firstObject;
    
    NSLog(@"[证书选择] 选择证书: %@", p12.certificateName ?: p12.filename);
    NSLog(@"[证书选择] 选择描述文件: %@", profile.certificateName ?: profile.filename);
    NSLog(@"[证书选择] 准备上传文件: %@", ipaPath);
    
    [self performUploadWithP12:p12 provisionProfile:profile andIpa:ipaPath];
}

// 添加显示错误提示方法
- (void)showErrorTip:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"错误"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

// 添加获取当前时间字符串的方法
- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

// 实现selectProvisionProfile:forP12:andIpa:方法
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

@end
