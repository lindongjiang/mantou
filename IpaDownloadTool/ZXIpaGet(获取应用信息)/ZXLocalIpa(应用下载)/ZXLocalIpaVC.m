//
//  ZXLocalIpaVC.m
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/29.
//  Copyright © 2019 李兆祥. All rights reserved.
//  https://github.com/SmileZXLee/IpaDownloadTool

#import "ZXLocalIpaVC.h"
#import "ZXLocalIpaDownloadCell.h"
#import "ZXLocalIpaDownloadModel.h"
#import "UIViewController+BackButtonHandler.h"
typedef enum {
    DownloadTypeDownloading = 0x00,    // 下载中
    DownloadTypeDownloaded = 0x01,    // 已下载
    
}DownloadType;
@interface ZXLocalIpaVC ()<UIGestureRecognizerDelegate>
@property (weak, nonatomic) IBOutlet UISegmentedControl *segView;
@property (weak, nonatomic) IBOutlet ZXTableView *tableView;
@property (assign, nonatomic) DownloadType downloadType;
@property (strong, nonatomic) ZXFileDownload *fileDownload;
@property(strong, nonatomic) NSURLSession *downloadSession;
@property(strong, nonatomic) NSURLConnection *downloadConnection;
@property (strong, nonatomic) ZXLocalIpaDownloadModel *downloadingModel;
@end

@implementation ZXLocalIpaVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initUI];
}
#pragma mark - 初始化视图
-(void)initUI{
    self.title = MainTitle;
    if ([self.navigationController respondsToSelector:@selector(interactivePopGestureRecognizer)]) {
        self.navigationController.interactivePopGestureRecognizer.delegate = self;
    }
    __weak __typeof(self) weakSelf = self;
    [self.segView zx_obsKey:@"selectedSegmentIndex" handler:^(id newData, id oldData, id owner) {
        weakSelf.downloadType = [newData boolValue];
    }];
    
    // 如果有IPA模型但没有通过startDownloadWithIpaModel方法设置，则启动下载
    if(self.ipaModel && !self.downloadingModel){
        [self startDownloadWithIpaModel:self.ipaModel];
    }else{
        [self.segView setSelectedSegmentIndex:1];
        [self setDownloadedData];
    }
    
    self.segView.tintColor = MainColor;
    self.tableView.zx_setCellClassAtIndexPath = ^Class(NSIndexPath *indexPath) {
        return [ZXLocalIpaDownloadCell class];
    };
    self.tableView.zx_didSelectedAtIndexPath = ^(NSIndexPath *indexPath, ZXLocalIpaDownloadModel *model, id cell) {
        if(model.isFinish && self.downloadType == DownloadTypeDownloaded){
            [[ZXFileManage shareInstance] shareFileWithPath:model.localPath];
        }
    };
    self.tableView.zx_editActionsForRowAtIndexPath = ^NSArray<UITableViewRowAction *> *(NSIndexPath *indexPath) {
        UITableViewRowAction *delAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"删除" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            ZXLocalIpaDownloadModel *model = weakSelf.tableView.zxDatas[indexPath.row];
            [ZXFileManage delFileWithPath:model.localPath];
            if(self.downloadType == DownloadTypeDownloaded){
                [weakSelf setDownloadedData];
            }
        }];
        return self.downloadType == DownloadTypeDownloaded ? @[delAction] : @[];
    };
    self.navigationItem.titleView = self.segView;
}
#pragma mark - Actions
#pragma mark 切换下载中与已下载
- (IBAction)segChangeAction:(id)sender {
    self.downloadType = (BOOL)self.segView.selectedSegmentIndex;
    [self removePlaceView];
    [self.tableView.zxDatas removeAllObjects];
    
    if(self.downloadType == DownloadTypeDownloaded){
        [self setDownloadedData];
    }else{
        // 如果有正在下载的任务，显示下载任务
        if(self.downloadingModel && !self.downloadingModel.isFinish){
            [self.tableView.zxDatas addObject:self.downloadingModel];
            [self.tableView reloadData];
            [self removePlaceView];
        }else{
            [self showPlaceViewWithText:@"暂无下载中的文件"];
        }
    }
}

#pragma mark - Private
#pragma mark 开始下载
-(void)startDownload{
    // 移除注释掉的代码，确保不会重复添加下载模型
    // if(self.ipaModel && self.downloadType == DownloadTypeDownloading){
    //     [self.tableView.zxDatas addObject:self.downloadingModel];
    // }
    
    NSLog(@"[ZXLocalIpaVC] 开始下载任务: %@", self.ipaModel.downloadUrl);
    self.fileDownload = [[ZXFileDownload alloc]init];
    __weak __typeof(self) weakSelf = self;
    self.downloadConnection = [self.fileDownload downLoadWithUrlStrByURLConnection:self.ipaModel.downloadUrl filePath:self.downloadingModel.localPath callBack:^(BOOL result, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite, NSString * _Nonnull path) {
        if(result){
            weakSelf.downloadingModel.totalBytesWritten = totalBytesWritten;
            weakSelf.downloadingModel.totalBytesExpectedToWrite = totalBytesExpectedToWrite;
            if(totalBytesExpectedToWrite == totalBytesWritten && totalBytesExpectedToWrite && totalBytesExpectedToWrite > 1024){
                weakSelf.downloadingModel.finish = YES;
                [weakSelf.ipaModel zx_dbUpdateWhere:[NSString stringWithFormat:@"sign='%@'",weakSelf.ipaModel.sign]];
                [weakSelf.segView setSelectedSegmentIndex:1];
                [weakSelf setDownloadedData];
            }else if(!totalBytesExpectedToWrite){
                weakSelf.downloadingModel.finish = YES;
                weakSelf.downloadingModel.totalBytesWritten = 0;
                weakSelf.downloadingModel.totalBytesExpectedToWrite = 0;
            }
        }else{
            weakSelf.downloadingModel.finish = YES;
        }
        [weakSelf.tableView reloadData];
    }];
}

#pragma mark 设置已下载数据
-(void)setDownloadedData{
    [self.tableView.zxDatas removeAllObjects];
    NSArray *resArr = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"localPath!=''"]];
    for (int i = (int)(resArr.count - 1);i >= 0;i--) {
        ZXIpaModel *ipaModel = resArr[i];
        ZXLocalIpaDownloadModel *downloadedModel = [[ZXLocalIpaDownloadModel alloc]init];
        if(ipaModel.version){
            downloadedModel.title = [NSString stringWithFormat:@"%@(v%@).ipa",ipaModel.title,ipaModel.version];
        }else{
            downloadedModel.title = [NSString stringWithFormat:@"%@.ipa",ipaModel.title];
        }
        downloadedModel.downloadUrl = ipaModel.downloadUrl;
        downloadedModel.sign = ipaModel.sign;
        downloadedModel.finish = YES;
        downloadedModel.localPath = ipaModel.localPath;
        downloadedModel.totalBytesExpectedToWrite = [ZXFileManage getFileSizeWithPath:downloadedModel.localPath];
        if([ZXFileManage isExistWithPath:downloadedModel.localPath] && downloadedModel.totalBytesExpectedToWrite > 3000){
            [self.tableView.zxDatas addObject:downloadedModel];
        }
    }
    [self.tableView reloadData];
    if(!self.tableView.zxDatas.count){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showPlaceViewWithText:@"暂无已下载的文件"];
        });
    }
}

#pragma mark 设置下载中数据
-(void)setDownloadingData{
    [self.tableView.zxDatas removeAllObjects];
    
    // 如果有当前正在下载的模型，添加到列表
    if (self.downloadingModel && !self.downloadingModel.isFinish) {
        // 检查是否已经存在相同的下载任务
        BOOL alreadyExists = NO;
        for (ZXLocalIpaDownloadModel *model in self.tableView.zxDatas) {
            if ([model.sign isEqualToString:self.downloadingModel.sign]) {
                alreadyExists = YES;
                break;
            }
        }
        
        if (!alreadyExists) {
            [self.tableView.zxDatas addObject:self.downloadingModel];
        }
    }
    
    [self.tableView reloadData];
    
    if (!self.tableView.zxDatas.count) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showPlaceViewWithText:@"暂无下载中的文件"];
        });
    } else {
        [self removePlaceView];
    }
}

#pragma mark 控制器pop时显示提示信息
-(BOOL)showBlockNotice{
    if(self.ipaModel && self.downloadingModel && !self.downloadingModel.isFinish){
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前有任务正在下载中，关闭页面将会取消当前任务" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:nil];
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"关闭页面" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self.navigationController popViewControllerAnimated:YES];
            //[self.downloadSession invalidateAndCancel];
            [self.downloadConnection cancel];
            if(self.downloadingModel.localPath){
                [ZXFileManage delFileWithPath:self.downloadingModel.localPath];
            }
        }];
        [alertController addThemeAction:cancelAction];
        [alertController addThemeAction:confirmAction];
        [self presentViewController:alertController animated:YES completion:nil];
        return YES;
    }
    return NO;
}
#pragma mark 拦截侧滑返回手势
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return ![self showBlockNotice];
}

#pragma mark 拦截点击返回
-(BOOL)navigationShouldPopOnBackButton{
    return ![self showBlockNotice];
}

#pragma mark - 懒加载
-(ZXLocalIpaDownloadModel *)downloadingModel{
    if(!_downloadingModel){
        _downloadingModel = [[ZXLocalIpaDownloadModel alloc]init];
        _downloadingModel.downloadUrl = self.ipaModel.downloadUrl;
        if(self.ipaModel.version){
            _downloadingModel.title = [NSString stringWithFormat:@"%@(v%@).ipa",self.ipaModel.title,self.ipaModel.version];
        }else{
            _downloadingModel.title = [NSString stringWithFormat:@"%@.ipa",self.ipaModel.title];
        }
        _downloadingModel.sign = self.ipaModel.sign;
        _downloadingModel.localPath = self.ipaModel.localPath;
    }
    return _downloadingModel;
}

#pragma mark - Public Methods

// 刷新数据
- (void)refreshData {
    // 根据当前选中的分段控件刷新相应的数据
    if (self.downloadType == DownloadTypeDownloading) {
        // 刷新下载中的数据
        [self setDownloadingData];
    } else {
        // 刷新已下载的数据
        [self setDownloadedData];
    }
}

// 开始下载IPA
- (void)startDownloadWithIpaModel:(ZXIpaModel *)ipaModel {
    NSLog(@"[ZXLocalIpaVC] 开始下载IPA: %@, URL: %@", ipaModel.title, ipaModel.downloadUrl);
    
    // 检查是否已经存在相同的下载任务
    if (self.downloadingModel && 
        !self.downloadingModel.isFinish && 
        [self.downloadingModel.sign isEqualToString:ipaModel.sign]) {
        NSLog(@"[ZXLocalIpaVC] 已存在相同的下载任务，不重复添加");
        
        // 切换到下载中标签
        self.segView.selectedSegmentIndex = DownloadTypeDownloading;
        self.downloadType = DownloadTypeDownloading;
        
        // 刷新下载中数据
        [self setDownloadingData];
        return;
    }
    
    // 保存IPA模型
    self.ipaModel = ipaModel;
    
    // 切换到下载中标签
    self.segView.selectedSegmentIndex = DownloadTypeDownloading;
    self.downloadType = DownloadTypeDownloading;
    
    // 清除旧数据
    [self.tableView.zxDatas removeAllObjects];
    
    // 创建下载模型
    self.downloadingModel = [[ZXLocalIpaDownloadModel alloc] init];
    self.downloadingModel.downloadUrl = ipaModel.downloadUrl;
    
    if (ipaModel.version) {
        self.downloadingModel.title = [NSString stringWithFormat:@"%@(v%@).ipa", ipaModel.title, ipaModel.version];
    } else {
        self.downloadingModel.title = [NSString stringWithFormat:@"%@.ipa", ipaModel.title];
    }
    
    self.downloadingModel.sign = ipaModel.sign;
    self.downloadingModel.localPath = ipaModel.localPath;
    self.downloadingModel.finish = NO;
    
    // 添加到表格数据
    [self.tableView.zxDatas addObject:self.downloadingModel];
    [self.tableView reloadData];
    
    // 开始下载
    [self startDownload];
    
    // 移除占位视图
    [self removePlaceView];
}

// 重写setIpaModel方法，使用startDownloadWithIpaModel方法处理
- (void)setIpaModel:(ZXIpaModel *)ipaModel {
    // 如果已经有相同的下载任务，不重复添加
    if (_ipaModel && [_ipaModel.sign isEqualToString:ipaModel.sign]) {
        NSLog(@"[ZXLocalIpaVC] 已存在相同的下载任务，不重复添加");
        return;
    }
    
    _ipaModel = ipaModel;
    
    // 如果已经加载视图，则开始下载
    if (self.isViewLoaded) {
        [self startDownloadWithIpaModel:ipaModel];
    }
}

@end
