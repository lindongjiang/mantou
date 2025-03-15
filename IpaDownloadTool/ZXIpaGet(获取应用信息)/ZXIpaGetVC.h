//
//  ZXIpaGetVC.h
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/28.
//  Copyright © 2019 李兆祥. All rights reserved.
//  https://github.com/SmileZXLee/IpaDownloadTool

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaGetVC : UIViewController

// 处理URL字符串
- (void)handelWithUrlStr:(NSString *)urlStr;

// 处理URL输入来源
- (void)handleInputUrlFrom:(NSInteger)from;

@end

NS_ASSUME_NONNULL_END
