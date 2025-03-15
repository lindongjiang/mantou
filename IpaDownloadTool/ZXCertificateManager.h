//
//  ZXCertificateManager.h
//  IpaDownloadTool
//
//  Created on 2024/7/13.
//  Copyright © 2024. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXCertificateModel : NSObject

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *filepath;
@property (nonatomic, copy) NSString *certificateType; // p12 或 mobileprovision
@property (nonatomic, copy) NSString *teamID; // 团队ID
@property (nonatomic, copy) NSString *certificateName; // 证书名称
@property (nonatomic, strong) NSDate *expirationDate; // 证书过期时间

@end

@interface ZXCertificateManager : NSObject

+ (instancetype)sharedManager;

// 获取所有P12证书
- (NSArray<ZXCertificateModel *> *)allP12Certificates;

// 获取所有描述文件
- (NSArray<ZXCertificateModel *> *)allProvisionProfiles;

// 保存P12证书
- (BOOL)saveP12Certificate:(NSData *)certificateData withFilename:(NSString *)filename password:(NSString *)password;

// 保存描述文件
- (BOOL)saveProvisionProfile:(NSData *)profileData withFilename:(NSString *)filename;

// 删除证书
- (BOOL)deleteCertificate:(ZXCertificateModel *)certificate;

// 验证P12证书与描述文件是否匹配
- (BOOL)verifyP12Certificate:(ZXCertificateModel *)p12Certificate 
        withProvisionProfile:(ZXCertificateModel *)provisionProfile;

// 获取证书存储目录
- (NSString *)certificatesDirectory;

// 重新加载证书
- (void)reloadCertificates;

// 获取P12证书的密码
- (NSString *)passwordForP12Certificate:(ZXCertificateModel *)certificate;

@end

NS_ASSUME_NONNULL_END 