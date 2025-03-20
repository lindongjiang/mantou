//
//  ZXIpaModel.h
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/28.
//  Copyright © 2019 李兆祥. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaModel : NSObject
///下载链接
@property (copy, nonatomic) NSString *downloadUrl;
///icon链接
@property (copy, nonatomic) NSString *iconUrl;
///bundleId
@property (copy, nonatomic) NSString *bundleId;
///版本号
@property (copy, nonatomic) NSString *version;
///应用名称
@property (copy, nonatomic) NSString *title;
///创建时间
@property (copy, nonatomic) NSString *time;
///下载来源链接
@property (copy, nonatomic) NSString *fromPageUrl;
///唯一标识
@property (copy, nonatomic) NSString *sign;
///ipa保存本地地址
@property (copy, nonatomic) NSString *localPath;
///是否已签名
@property (assign, nonatomic) BOOL isSigned;
///签名时间
@property (copy, nonatomic) NSString *signedTime;
///安装链接
@property (copy, nonatomic) NSString *installLink;
-(instancetype)initWithDic:(NSDictionary *)dic;
@end

NS_ASSUME_NONNULL_END
