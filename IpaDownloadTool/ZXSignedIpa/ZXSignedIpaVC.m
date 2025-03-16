//
//  ZXSignedIpaVC.m
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import "ZXSignedIpaVC.h"
#import "ZXIpaManager.h"
#import "ZXIpaModel.h"
#import "ZXIpaCell.h"
#import "ZXIpaDetailVC.h"
#import "NSString+ZXMD5.h"

@interface ZXSignedIpaVC () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<ZXIpaModel *> *signedIpaList;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation ZXSignedIpaVC

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"已签名";
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 每次页面出现时刷新数据
    [self loadSignedIpas];
}

#pragma mark - UI设置

- (void)setupUI {
    // 创建表格视图
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 80;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.tableFooterView = [UIView new];
    [self.view addSubview:self.tableView];
    
    // 注册单元格
    [self.tableView registerClass:[ZXIpaCell class] forCellReuseIdentifier:@"ZXIpaCell"];
    
    // 创建空视图标签
    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    self.emptyLabel.center = self.view.center;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.text = @"暂无已签名的IPA文件";
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

#pragma mark - 数据加载

- (void)loadSignedIpas {
    // 获取所有已签名的IPA
    self.signedIpaList = [[ZXIpaManager sharedManager] allSignedIpas];
    
    // 更新UI
    [self.tableView reloadData];
    
    // 显示或隐藏空视图
    self.emptyLabel.hidden = self.signedIpaList.count > 0;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.signedIpaList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZXIpaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ZXIpaCell" forIndexPath:indexPath];
    
    // 获取当前IPA模型
    ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
    
    // 设置单元格数据
    cell.titleLabel.text = ipaModel.title;
    cell.subtitleLabel.text = [NSString stringWithFormat:@"版本: %@", ipaModel.version];
    cell.detailLabel.text = [NSString stringWithFormat:@"签名时间: %@", ipaModel.signedTime];
    
    // 设置图标
    if (ipaModel.iconUrl) {
        // 如果有本地图标路径，使用本地图标
        if ([ipaModel.iconUrl hasPrefix:@"/"]) {
            cell.iconImageView.image = [UIImage imageWithContentsOfFile:ipaModel.iconUrl];
        } else {
            // 否则使用默认图标
            cell.iconImageView.image = [UIImage imageNamed:@"default_app_icon"];
        }
    } else {
        cell.iconImageView.image = [UIImage imageNamed:@"default_app_icon"];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 获取选中的IPA模型
    ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
    
    // 跳转到详情页
    ZXIpaDetailVC *detailVC = [[ZXIpaDetailVC alloc] init];
    detailVC.ipaModel = ipaModel;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"删除";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // 获取要删除的IPA模型
        ZXIpaModel *ipaModel = self.signedIpaList[indexPath.row];
        
        // 删除IPA
        BOOL success = [[ZXIpaManager sharedManager] deleteSignedIpa:ipaModel];
        
        if (success) {
            // 更新数据源
            NSMutableArray *mutableList = [self.signedIpaList mutableCopy];
            [mutableList removeObjectAtIndex:indexPath.row];
            self.signedIpaList = [mutableList copy];
            
            // 更新表格
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            
            // 检查是否需要显示空视图
            self.emptyLabel.hidden = self.signedIpaList.count > 0;
        }
    }
}

- (void)saveSignedIpaToDatabase:(NSString *)ipaPath withOriginalIpa:(ZXIpaModel *)originalIpa {
    NSLog(@"[签名数据库] 开始保存已签名的IPA到数据库");
    
    // 创建新的IPA模型
    ZXIpaModel *signedIpa = [[ZXIpaModel alloc] init];
    signedIpa.localPath = ipaPath;
    signedIpa.title = [NSString stringWithFormat:@"%@ (已签名)", originalIpa.title];
    signedIpa.bundleId = originalIpa.bundleId;
    signedIpa.version = originalIpa.version;
    signedIpa.iconUrl = originalIpa.iconUrl;
    signedIpa.time = [self currentTimeString];
    signedIpa.isSigned = YES;
    signedIpa.signedTime = [self currentTimeString];
    
    // 生成唯一标识
    NSString *uniqueString = [NSString stringWithFormat:@"%@_%@_signed", originalIpa.bundleId, originalIpa.version];
    signedIpa.sign = [uniqueString md5Str];
    
    // 保存到数据库
    [[ZXIpaManager sharedManager] saveSignedIpa:signedIpa];
    
    NSLog(@"[签名数据库] 已签名的IPA已保存到数据库");
}

#pragma mark - 辅助方法

- (NSString *)currentTimeString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

@end 