//
//  ZXIpaDetailVC.h
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/29.
//  Copyright © 2019 李兆祥. All rights reserved.
//  https://github.com/SmileZXLee/IpaDownloadTool

#import <UIKit/UIKit.h>
#import "ZXIpaModel.h"
#import "ZXCertificateManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaDetailVC : UIViewController
@property (strong, nonatomic) ZXIpaModel *ipaModel;
@property (nonatomic, copy) NSString *p12Password;
@property (nonatomic, copy) NSString *signedIpaDownloadUrl;

// 签名相关方法
- (void)startSigningWithP12:(ZXCertificateModel *)p12Cert provisionProfile:(ZXCertificateModel *)profile andIpa:(ZXIpaModel *)ipaModel;
- (void)selectProvisionProfile:(NSArray<ZXCertificateModel *> *)profiles forP12:(ZXCertificateModel *)p12Cert andIpa:(ZXIpaModel *)ipaModel;
- (void)signIpaFile:(NSString *)ipaPath;
- (void)performUploadWithP12:(ZXCertificateModel *)p12 provisionProfile:(ZXCertificateModel *)provisionProfile andIpa:(NSString *)ipaPath;

// 辅助方法
- (void)showWarningTip:(NSString *)message;
- (void)showSuccessTip:(NSString *)message;
- (void)showCertificateSelectorWithP12Certificates:(NSArray *)p12Certificates provisionProfiles:(NSArray *)provisionProfiles ipaPath:(NSString *)ipaPath;
@end

NS_ASSUME_NONNULL_END
