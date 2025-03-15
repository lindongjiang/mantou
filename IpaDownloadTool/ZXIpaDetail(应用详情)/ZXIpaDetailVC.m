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
@interface ZXIpaDetailVC ()
@property (weak, nonatomic) IBOutlet ZXTableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIView *overlayView;
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
    // 检查IPA文件是否已下载
    if (![ZXFileManage isExistWithPath:self.ipaModel.localPath]) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                 message:@"请先下载IPA文件再进行签名"
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
        [alertController addThemeAction:okAction];
        [self presentViewController:alertController animated:YES completion:nil];
        return;
    }
    
    // 获取证书列表
    ZXCertificateManager *certificateManager = [ZXCertificateManager sharedManager];
    NSArray *p12Certificates = [certificateManager allP12Certificates];
    NSArray *provisionProfiles = [certificateManager allProvisionProfiles];
    
    // 检查是否有可用的证书
    if (p12Certificates.count == 0 || provisionProfiles.count == 0) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                 message:@"请先导入证书和描述文件"
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *goToAction = [UIAlertAction actionWithTitle:@"去导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            ZXCertificateManageVC *VC = [[ZXCertificateManageVC alloc] init];
            [self.navigationController pushViewController:VC animated:YES];
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        [alertController addThemeAction:goToAction];
        [alertController addThemeAction:cancelAction];
        [self presentViewController:alertController animated:YES completion:nil];
        return;
    }
    
    // 显示证书选择界面
    [self showCertificateSelectionAlert];
}

- (void)showCertificateSelectionAlert {
    ZXCertificateManager *certificateManager = [ZXCertificateManager sharedManager];
    NSArray *p12Certificates = [certificateManager allP12Certificates];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择证书"
                                                                             message:@"请选择用于签名的证书"
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (ZXCertificateModel *p12Model in p12Certificates) {
        NSString *title = p12Model.certificateName ?: p12Model.filename;
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            // 查找匹配的描述文件
            NSArray *provisionProfiles = [certificateManager allProvisionProfiles];
            ZXCertificateModel *matchingProfile = nil;
            
            for (ZXCertificateModel *provisionModel in provisionProfiles) {
                if ([certificateManager verifyP12Certificate:p12Model withProvisionProfile:provisionModel]) {
                    matchingProfile = provisionModel;
                    break;
                }
            }
            
            if (matchingProfile) {
                // 开始签名过程
                [self startSigningWithP12:p12Model andProvisionProfile:matchingProfile];
            } else {
                // 没有找到匹配的描述文件
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"错误"
                                                                                    message:@"没有找到与该证书匹配的描述文件"
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                [errorAlert addThemeAction:okAction];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
        }];
        [alertController addThemeAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alertController addThemeAction:cancelAction];
    
    // 在iPad上需要设置弹出位置
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = self.view;
        alertController.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
        alertController.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)startSigningWithP12:(ZXCertificateModel *)p12Model andProvisionProfile:(ZXCertificateModel *)provisionProfile {
    // 显示加载指示器
    self.overlayView.hidden = NO;
    [self.activityIndicator startAnimating];
    
    // 获取证书密码
    NSString *password = [[ZXCertificateManager sharedManager] passwordForP12Certificate:p12Model];
    
    // 准备上传参数
    NSString *bundleId = self.ipaModel.bundleId;
    NSURL *ipaURL = [NSURL fileURLWithPath:self.ipaModel.localPath];
    NSURL *p12URL = [NSURL fileURLWithPath:p12Model.filepath];
    
    // 创建会话配置
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    
    // 创建请求
    NSURL *url = [NSURL URLWithString:@"https://ipa.cloudmantoub.online/index/index/uploads"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // 生成边界字符串
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    // 创建请求体
    NSMutableData *body = [NSMutableData data];
    
    // 添加IPA文件
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file[]\"; filename=\"%@\"\r\n", ipaURL.lastPathComponent] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfURL:ipaURL]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加P12文件
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file[]\"; filename=\"%@\"\r\n", p12URL.lastPathComponent] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfURL:p12URL]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加密码
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"password\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[password dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 添加bundleId
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"bundleid\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[bundleId dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 结束边界
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 设置请求体
    request.HTTPBody = body;
    
    // 发送请求
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 隐藏加载指示器
            self.overlayView.hidden = YES;
            [self.activityIndicator stopAnimating];
            
            if (error) {
                // 处理错误
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名失败"
                                                                                         message:[NSString stringWithFormat:@"错误: %@", error.localizedDescription]
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                [alertController addThemeAction:okAction];
                [self presentViewController:alertController animated:YES completion:nil];
                return;
            }
            
            // 解析响应
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                NSError *jsonError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    // JSON解析错误
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名失败"
                                                                                             message:@"无法解析服务器响应"
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                    [alertController addThemeAction:okAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                    return;
                }
                
                // 检查响应状态
                NSInteger code = [jsonResponse[@"code"] integerValue];
                NSString *msg = jsonResponse[@"msg"];
                
                if (code == 200) {
                    // 签名成功，下载已签名的IPA
                    NSDictionary *data = jsonResponse[@"data"];
                    NSString *downloadUrl = data[@"url"];
                    
                    if (downloadUrl) {
                        [self downloadSignedIpa:downloadUrl];
                    } else {
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名失败"
                                                                                                 message:@"服务器未返回下载链接"
                                                                                          preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                        [alertController addThemeAction:okAction];
                        [self presentViewController:alertController animated:YES completion:nil];
                    }
                } else {
                    // 签名失败
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名失败"
                                                                                             message:msg ?: @"未知错误"
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                    [alertController addThemeAction:okAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                }
            } else {
                // HTTP错误
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名失败"
                                                                                         message:[NSString stringWithFormat:@"服务器返回错误: %ld", (long)httpResponse.statusCode]
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                [alertController addThemeAction:okAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
        });
    }];
    
    [task resume];
}

- (void)downloadSignedIpa:(NSString *)downloadUrl {
    // 显示加载指示器
    self.overlayView.hidden = NO;
    [self.activityIndicator startAnimating];
    
    // 创建会话配置
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    
    // 创建下载任务
    NSURL *url = [NSURL URLWithString:downloadUrl];
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 隐藏加载指示器
            self.overlayView.hidden = YES;
            [self.activityIndicator stopAnimating];
            
            if (error) {
                // 处理下载错误
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"下载失败"
                                                                                         message:[NSString stringWithFormat:@"错误: %@", error.localizedDescription]
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                [alertController addThemeAction:okAction];
                [self presentViewController:alertController animated:YES completion:nil];
                return;
            }
            
            // 保存已签名的IPA
            NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *signedIpaPath = [documentsPath stringByAppendingPathComponent:@"SignedIpa"];
            
            // 确保目录存在
            if (![ZXFileManage fileExistWithPath:signedIpaPath]) {
                [ZXFileManage creatDirWithPath:signedIpaPath];
            }
            
            // 创建文件名
            NSString *fileName = [NSString stringWithFormat:@"%@_signed.ipa", self.ipaModel.title];
            NSString *filePath = [signedIpaPath stringByAppendingPathComponent:fileName];
            
            // 移动文件
            NSError *moveError;
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:filePath] error:&moveError];
            
            if (moveError) {
                // 处理移动错误
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                                         message:[NSString stringWithFormat:@"错误: %@", moveError.localizedDescription]
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
                [alertController addThemeAction:okAction];
                [self presentViewController:alertController animated:YES completion:nil];
                return;
            }
            
            // 创建已签名IPA的模型
            ZXIpaModel *signedIpaModel = [[ZXIpaModel alloc] init];
            signedIpaModel.title = [NSString stringWithFormat:@"%@ (已签名)", self.ipaModel.title];
            signedIpaModel.version = self.ipaModel.version;
            signedIpaModel.bundleId = self.ipaModel.bundleId;
            signedIpaModel.iconUrl = self.ipaModel.iconUrl;
            signedIpaModel.downloadUrl = downloadUrl;
            signedIpaModel.fromPageUrl = self.ipaModel.fromPageUrl;
            signedIpaModel.localPath = filePath;
            signedIpaModel.isSigned = YES;
            signedIpaModel.signedTime = [self currentTimeString];
            
            // 生成唯一标识
            NSString *uniqueString = [NSString stringWithFormat:@"%@_%@_signed", self.ipaModel.bundleId, self.ipaModel.version];
            signedIpaModel.sign = [uniqueString md5Str];
            
            // 保存到数据库
            [signedIpaModel zx_dbSave];
            
            // 显示成功提示
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"签名成功"
                                                                                     message:@"IPA已成功签名并保存"
                                                                              preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *viewAction = [UIAlertAction actionWithTitle:@"查看已签名IPA" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                ZXSignedIpaVC *VC = [[ZXSignedIpaVC alloc] init];
                [self.navigationController pushViewController:VC animated:YES];
            }];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
            [alertController addThemeAction:viewAction];
            [alertController addThemeAction:okAction];
            [self presentViewController:alertController animated:YES completion:nil];
        });
    }];
    
    [downloadTask resume];
}

- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

@end
