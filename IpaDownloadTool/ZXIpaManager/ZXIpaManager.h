//
//  ZXIpaManager.h
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import <Foundation/Foundation.h>
#import "ZXIpaModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaManager : NSObject

+ (instancetype)sharedManager;

/**
 保存已签名的IPA文件信息到数据库
 
 @param ipaModel 已签名的IPA模型
 @return 是否保存成功
 */
- (BOOL)saveSignedIpa:(ZXIpaModel *)ipaModel;

/**
 获取所有已签名的IPA文件
 
 @return 已签名的IPA模型数组
 */
- (NSArray<ZXIpaModel *> *)allSignedIpas;

/**
 删除已签名的IPA文件
 
 @param ipaModel 要删除的IPA模型
 @return 是否删除成功
 */
- (BOOL)deleteSignedIpa:(ZXIpaModel *)ipaModel;

@end

NS_ASSUME_NONNULL_END 