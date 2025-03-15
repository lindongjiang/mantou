//
//  ZXSignedIpaVC.m
//  IpaDownloadTool
//
//  Created on 2024/7/13.
//  Copyright © 2024. All rights reserved.
//

#import "ZXSignedIpaVC.h"
#import "ZXIpaModel.h"
#import "ZXFileManage.h"

@interface ZXSignedIpaVC () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<ZXIpaModel *> *signedIpaList;
@property (nonatomic, strong) UIView *emptyView;

@end

@implementation ZXSignedIpaVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已签名IPA";
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self setupUI];
    [self loadSignedIpaFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadSignedIpaFiles];
}

#pragma mark - UI设置
- (void)setupUI {
    // 创建表格视图
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [UIView new]; // 去除空白cell的分割线
    [self.view addSubview:self.tableView];
    
    // 注册单元格
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SignedIpaCell"];
    
    // 创建空视图
    self.emptyView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.emptyView.backgroundColor = [UIColor whiteColor];
    
    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = @"暂无已签名的IPA文件";
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.textColor = [UIColor grayColor];
    emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:emptyLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [emptyLabel.centerXAnchor constraintEqualToAnchor:self.emptyView.centerXAnchor],
        [emptyLabel.centerYAnchor constraintEqualToAnchor:self.emptyView.centerYAnchor]
    ]];
    
    self.emptyView.hidden = YES;
    [self.view addSubview:self.emptyView];
}

#pragma mark - 加载已签名IPA文件
- (void)loadSignedIpaFiles {
    if (!self.signedIpaList) {
        self.signedIpaList = [NSMutableArray array];
    } else {
        [self.signedIpaList removeAllObjects];
    }
    
    // 获取已签名IPA的目录路径
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *signedIpaPath = [documentsPath stringByAppendingPathComponent:@"SignedIpa"];
    
    // 确保目录存在
    if (![ZXFileManage fileExistWithPath:signedIpaPath]) {
        [ZXFileManage creatDirWithPath:signedIpaPath];
    }
    
    // 从数据库加载已签名的IPA信息
    NSArray *signedIpaModels = [ZXIpaModel zx_dbQuaryWhere:@"isSigned = 1"];
    
    for (ZXIpaModel *ipaModel in signedIpaModels) {
        // 检查文件是否存在
        if ([ZXFileManage fileExistWithPath:ipaModel.localPath]) {
            [self.signedIpaList addObject:ipaModel];
        } else {
            // 如果文件不存在，从数据库中删除记录
            [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
        }
    }
    
    [self.tableView reloadData];
    
    // 显示或隐藏空视图
    if (self.signedIpaList.count == 0) {
        self.emptyView.hidden = NO;
    } else {
        self.emptyView.hidden = YES;
    }
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.signedIpaList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SignedIpaCell" forIndexPath:indexPath];
    
    ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
    
    cell.textLabel.text = ipaModel.title;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"版本: %@", ipaModel.version];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"操作选择"
                                                                             message:@"请选择您要进行的操作"
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *installAction = [UIAlertAction actionWithTitle:@"安装到设备"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
        [self installIpa:ipaModel];
    }];
    
    UIAlertAction *shareAction = [UIAlertAction actionWithTitle:@"分享文件"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [[ZXFileManage shareInstance] shareFileWithPath:ipaModel.localPath];
    }];
    
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"删除"
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self deleteIpa:ipaModel atIndexPath:indexPath];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alertController addThemeAction:installAction];
    [alertController addThemeAction:shareAction];
    [alertController addThemeAction:deleteAction];
    [alertController addThemeAction:cancelAction];
    
    // 在iPad上需要设置弹出位置
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = tableView;
        alertController.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
        [self deleteIpa:ipaModel atIndexPath:indexPath];
    }
}

#pragma mark - 操作方法
// 安装IPA到设备
- (void)installIpa:(ZXIpaModel *)ipaModel {
    // 创建itms-services URL
    NSString *manifestUrl = [NSString stringWithFormat:@"itms-services://?action=download-manifest&url=https://ipa.cloudmantoub.online/plist/%@", ipaModel.sign];
    
    // 打开URL安装应用
    NSURL *url = [NSURL URLWithString:manifestUrl];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [ALToastView showToastWithText:@"无法安装应用"];
    }
}

// 删除IPA文件
- (void)deleteIpa:(ZXIpaModel *)ipaModel atIndexPath:(NSIndexPath *)indexPath {
    // 删除文件
    if ([ZXFileManage fileExistWithPath:ipaModel.localPath]) {
        [ZXFileManage delFileWithPath:ipaModel.localPath];
    }
    
    // 从数据库删除记录
    [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
    
    // 更新UI
    [self.signedIpaList removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    
    // 检查是否需要显示空视图
    if (self.signedIpaList.count == 0) {
        self.emptyView.hidden = NO;
    }
}

@end 