//
//  ZXCertificateManager.m
//  IpaDownloadTool
//
//  Created on 2024/7/13.
//  Copyright © 2024. All rights reserved.
//

#import "ZXCertificateManager.h"
#import <Security/Security.h>

@implementation ZXCertificateModel
@end

@interface ZXCertificateManager ()

@property (nonatomic, strong) NSMutableArray<ZXCertificateModel *> *p12Certificates;
@property (nonatomic, strong) NSMutableArray<ZXCertificateModel *> *provisionProfiles;
@property (nonatomic, strong) NSMutableDictionary *certificatePasswords; // 存储p12证书密码

@end

@implementation ZXCertificateManager

+ (instancetype)sharedManager {
    static ZXCertificateManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[ZXCertificateManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _p12Certificates = [NSMutableArray array];
        _provisionProfiles = [NSMutableArray array];
        _certificatePasswords = [NSMutableDictionary dictionary];
        
        // 从用户默认设置加载证书密码
        NSDictionary *savedPasswords = [[NSUserDefaults standardUserDefaults] objectForKey:@"ZXCertificatePasswords"];
        if (savedPasswords) {
            _certificatePasswords = [savedPasswords mutableCopy];
        }
        
        // 确保证书目录存在
        NSString *certificatesDir = [self certificatesDirectory];
        if (![[NSFileManager defaultManager] fileExistsAtPath:certificatesDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:certificatesDir 
                                     withIntermediateDirectories:YES 
                                                      attributes:nil 
                                                           error:nil];
        }
        
        // 加载已存在的证书
        [self reloadCertificates];
    }
    return self;
}

- (NSString *)certificatesDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return [documentsDirectory stringByAppendingPathComponent:@"Certificates"];
}

- (void)reloadCertificates {
    [self.p12Certificates removeAllObjects];
    [self.provisionProfiles removeAllObjects];
    
    NSString *certificatesDir = [self certificatesDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:certificatesDir error:nil];
    
    for (NSString *filename in files) {
        NSString *filepath = [certificatesDir stringByAppendingPathComponent:filename];
        
        ZXCertificateModel *model = [[ZXCertificateModel alloc] init];
        model.filename = filename;
        model.filepath = filepath;
        
        if ([filename.pathExtension.lowercaseString isEqualToString:@"p12"]) {
            model.certificateType = @"p12";
            // 从p12文件中获取信息
            [self extractP12Info:model];
            [self.p12Certificates addObject:model];
        } else if ([filename.pathExtension.lowercaseString isEqualToString:@"mobileprovision"]) {
            model.certificateType = @"mobileprovision";
            // 从mobileprovision文件中获取信息
            [self extractProvisionInfo:model];
            [self.provisionProfiles addObject:model];
        }
    }
}

- (NSArray<ZXCertificateModel *> *)allP12Certificates {
    return [self.p12Certificates copy];
}

- (NSArray<ZXCertificateModel *> *)allProvisionProfiles {
    return [self.provisionProfiles copy];
}

- (BOOL)saveP12Certificate:(NSData *)certificateData withFilename:(NSString *)filename password:(NSString *)password {
    // 验证p12证书是否有效
    NSDictionary *options = @{(id)kSecImportExportPassphrase: password};
    CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
    
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)certificateData, (__bridge CFDictionaryRef)options, &items);
    
    if (status != errSecSuccess) {
        if (items) {
            CFRelease(items);
        }
        return NO;
    }
    
    // 从证书中提取TeamID
    NSString *teamID = nil;
    if (items && CFArrayGetCount(items) > 0) {
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
        if (identityDict) {
            CFArrayRef certChain = CFDictionaryGetValue(identityDict, kSecImportItemCertChain);
            if (certChain && CFArrayGetCount(certChain) > 0) {
                SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certChain, 0);
                if (cert) {
                    CFStringRef commonName = NULL;
                    SecCertificateCopyCommonName(cert, &commonName);
                    if (commonName) {
                        NSString *name = (__bridge NSString *)commonName;
                        // 尝试从证书名称中提取TeamID
                        NSArray *components = [name componentsSeparatedByString:@"("];
                        if (components.count > 1) {
                            NSString *lastComponent = [components lastObject];
                            teamID = [[lastComponent componentsSeparatedByString:@")"] firstObject];
                        }
                        CFRelease(commonName);
                    }
                }
            }
        }
    }
    
    if (items) {
        CFRelease(items);
    }
    
    // 证书有效，保存到文件系统
    NSString *certificatesDir = [self certificatesDirectory];
    NSString *destinationPath = [certificatesDir stringByAppendingPathComponent:filename];
    
    BOOL success = [certificateData writeToFile:destinationPath atomically:YES];
    
    if (success) {
        // 保存证书密码
        [self.certificatePasswords setObject:password forKey:filename];
        [self savePasswords];
        
        // 重新加载证书
        [self reloadCertificates];
        
        // 如果提取到了TeamID，更新对应证书模型
        if (teamID) {
            for (ZXCertificateModel *model in self.p12Certificates) {
                if ([model.filename isEqualToString:filename]) {
                    model.teamID = teamID;
                    break;
                }
            }
        }
    }
    
    return success;
}

- (BOOL)saveProvisionProfile:(NSData *)profileData withFilename:(NSString *)filename {
    // 尝试解析描述文件，确保它是有效的
    NSString *profileText = [[NSString alloc] initWithData:profileData encoding:NSASCIIStringEncoding];
    
    if (!profileText) {
        return NO;
    }
    
    // 寻找plist部分
    NSRange plistStart = [profileText rangeOfString:@"<?xml"];
    NSRange plistEnd = [profileText rangeOfString:@"</plist>"];
    
    if (plistStart.location == NSNotFound || plistEnd.location == NSNotFound) {
        return NO;
    }
    
    // 保存到文件系统
    NSString *certificatesDir = [self certificatesDirectory];
    NSString *destinationPath = [certificatesDir stringByAppendingPathComponent:filename];
    
    BOOL success = [profileData writeToFile:destinationPath atomically:YES];
    
    if (success) {
        // 重新加载证书
        [self reloadCertificates];
    }
    
    return success;
}

- (BOOL)deleteCertificate:(ZXCertificateModel *)certificate {
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:certificate.filepath error:&error];
    
    if (success) {
        if ([certificate.certificateType isEqualToString:@"p12"]) {
            [self.p12Certificates removeObject:certificate];
            // 删除保存的密码
            [self.certificatePasswords removeObjectForKey:certificate.filename];
            [self savePasswords];
        } else if ([certificate.certificateType isEqualToString:@"mobileprovision"]) {
            [self.provisionProfiles removeObject:certificate];
        }
    }
    
    return success;
}

- (BOOL)verifyP12Certificate:(ZXCertificateModel *)p12Certificate withProvisionProfile:(ZXCertificateModel *)provisionProfile {
    // 如果两者都有teamID并且匹配，则认为匹配成功
    if (p12Certificate.teamID && provisionProfile.teamID && 
        [p12Certificate.teamID isEqualToString:provisionProfile.teamID]) {
        return YES;
    }
    
    // 如果TeamID为空，尝试重新提取信息
    if (!p12Certificate.teamID || !provisionProfile.teamID) {
        // 重新提取p12信息
        if (!p12Certificate.teamID) {
            [self extractP12Info:p12Certificate];
        }
        
        // 重新提取描述文件信息
        if (!provisionProfile.teamID) {
            [self extractProvisionInfo:provisionProfile];
        }
        
        // 再次检查TeamID
        if (p12Certificate.teamID && provisionProfile.teamID && 
            [p12Certificate.teamID isEqualToString:provisionProfile.teamID]) {
            return YES;
        }
    }
    
    // 如果仍然无法匹配，尝试使用证书内容进行更深层次的匹配
    NSString *password = [self passwordForP12Certificate:p12Certificate];
    if (password) {
        NSData *p12Data = [NSData dataWithContentsOfFile:p12Certificate.filepath];
        NSDictionary *options = @{(id)kSecImportExportPassphrase: password};
        CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
        
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
        
        if (status == errSecSuccess && items && CFArrayGetCount(items) > 0) {
            // 提取p12中的证书指纹
            NSMutableArray *p12Fingerprints = [NSMutableArray array];
            
            CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
            if (identityDict) {
                CFArrayRef certChain = CFDictionaryGetValue(identityDict, kSecImportItemCertChain);
                if (certChain) {
                    for (CFIndex i = 0; i < CFArrayGetCount(certChain); i++) {
                        SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certChain, i);
                        if (cert) {
                            NSData *certData = (__bridge_transfer NSData *)SecCertificateCopyData(cert);
                            if (certData) {
                                [p12Fingerprints addObject:certData];
                            }
                        }
                    }
                }
            }
            
            // 提取描述文件中的证书指纹
            NSData *profileData = [NSData dataWithContentsOfFile:provisionProfile.filepath];
            if (profileData) {
                NSString *profileText = [[NSString alloc] initWithData:profileData encoding:NSASCIIStringEncoding];
                NSRange plistStart = [profileText rangeOfString:@"<?xml"];
                NSRange plistEnd = [profileText rangeOfString:@"</plist>"];
                
                if (plistStart.location != NSNotFound && plistEnd.location != NSNotFound) {
                    NSRange plistRange = NSMakeRange(plistStart.location, plistEnd.location + plistEnd.length - plistStart.location);
                    NSString *plistText = [profileText substringWithRange:plistRange];
                    NSData *plistData = [plistText dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *plistDict = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:nil error:nil];
                    
                    NSArray *developerCerts = plistDict[@"DeveloperCertificates"];
                    if (developerCerts) {
                        for (NSData *provisionCertData in developerCerts) {
                            for (NSData *p12CertData in p12Fingerprints) {
                                if ([provisionCertData isEqualToData:p12CertData]) {
                                    // 找到匹配的证书
                                    if (items) {
                                        CFRelease(items);
                                    }
                                    return YES;
                                }
                            }
                        }
                    }
                }
            }
            
            if (items) {
                CFRelease(items);
            }
        }
    }
    
    return NO;
}

// 保存证书密码到用户默认设置
- (void)savePasswords {
    [[NSUserDefaults standardUserDefaults] setObject:self.certificatePasswords forKey:@"ZXCertificatePasswords"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 获取证书密码
- (NSString *)passwordForP12Certificate:(ZXCertificateModel *)certificate {
    return [self.certificatePasswords objectForKey:certificate.filename];
}

// 从p12文件中提取信息
- (void)extractP12Info:(ZXCertificateModel *)model {
    // 基本文件名作为证书名称
    model.certificateName = [model.filename stringByDeletingPathExtension];
    
    // 尝试使用保存的密码提取更多信息
    NSString *password = [self.certificatePasswords objectForKey:model.filename];
    if (password) {
        NSData *p12Data = [NSData dataWithContentsOfFile:model.filepath];
        NSDictionary *options = @{(id)kSecImportExportPassphrase: password};
        CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
        
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
        
        if (status == errSecSuccess && items && CFArrayGetCount(items) > 0) {
            CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
            if (identityDict) {
                CFArrayRef certChain = CFDictionaryGetValue(identityDict, kSecImportItemCertChain);
                if (certChain && CFArrayGetCount(certChain) > 0) {
                    SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certChain, 0);
                    if (cert) {
                        CFStringRef commonName = NULL;
                        SecCertificateCopyCommonName(cert, &commonName);
                        if (commonName) {
                            NSString *name = (__bridge NSString *)commonName;
                            // 尝试从证书名称中提取TeamID
                            NSArray *components = [name componentsSeparatedByString:@"("];
                            if (components.count > 1) {
                                NSString *lastComponent = [components lastObject];
                                model.teamID = [[lastComponent componentsSeparatedByString:@")"] firstObject];
                            }
                            CFRelease(commonName);
                        }
                    }
                }
            }
        }
        
        if (items) {
            CFRelease(items);
        }
    }
}

// 从mobileprovision文件中提取信息
- (void)extractProvisionInfo:(ZXCertificateModel *)model {
    // 解析mobileprovision文件
    NSString *profilePath = model.filepath;
    NSData *profileData = [NSData dataWithContentsOfFile:profilePath];
    
    if (profileData) {
        NSString *profileText = [[NSString alloc] initWithData:profileData encoding:NSASCIIStringEncoding];
        
        // 寻找plist部分
        NSRange plistStart = [profileText rangeOfString:@"<?xml"];
        NSRange plistEnd = [profileText rangeOfString:@"</plist>"];
        
        if (plistStart.location != NSNotFound && plistEnd.location != NSNotFound) {
            NSRange plistRange = NSMakeRange(plistStart.location, plistEnd.location + plistEnd.length - plistStart.location);
            NSString *plistText = [profileText substringWithRange:plistRange];
            
            // 将plist字符串转换为字典
            NSData *plistData = [plistText dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *plistDict = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:nil error:nil];
            
            // 提取信息
            model.certificateName = plistDict[@"Name"];
            
            // 提取TeamID
            NSArray *teamIdentifiers = plistDict[@"TeamIdentifier"];
            if (teamIdentifiers && teamIdentifiers.count > 0) {
                model.teamID = teamIdentifiers[0];
            } else {
                // 尝试从AppIDName中提取
                NSString *appIDName = plistDict[@"AppIDName"];
                if (appIDName) {
                    NSArray *components = [appIDName componentsSeparatedByString:@"("];
                    if (components.count > 1) {
                        NSString *lastComponent = [components lastObject];
                        model.teamID = [[lastComponent componentsSeparatedByString:@")"] firstObject];
                    }
                }
            }
            
            // 提取过期时间
            model.expirationDate = plistDict[@"ExpirationDate"];
        }
    }
}

@end 