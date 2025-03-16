//
//  ZXIpaImportVC.h
//  IpaDownloadTool
//
//  Created by ZX on 2020/4/5.
//  Copyright © 2020 ZX. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ZXCertificateManageVC.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaImportVC : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>

@property (nonatomic, strong) NSMutableArray *ipaList;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *importButton;

// 导入IPA文件
- (void)importIpaFile;

// 显示和隐藏空视图
- (void)showEmptyView;
- (void)hideEmptyView;

@end

NS_ASSUME_NONNULL_END 