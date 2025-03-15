//
//  ZXIpaImportVC.h
//  IpaDownloadTool
//
//  Created by ZX on 2020/4/5.
//  Copyright © 2020 ZX. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaImportVC : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) NSMutableArray *ipaList;

// 显示空视图
- (void)showEmptyView;
// 隐藏空视图
- (void)hideEmptyView;

@end

NS_ASSUME_NONNULL_END 