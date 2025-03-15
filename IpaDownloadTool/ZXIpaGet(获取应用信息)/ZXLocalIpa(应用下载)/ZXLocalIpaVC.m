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
    if(self.ipaModel){
        [self startDownload];
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
        if(!self.downloadingModel || self.downloadingModel.totalBytesExpectedToWrite == 0 || self.downloadingModel.isFinish){
            [self showPlaceViewWithText:@"暂无下载中的文件"];
        }else{
            [self.tableView.zxDatas addObject:self.downloadingModel];
        }
    }
    [self.tableView reloadData];
}

#pragma mark - Private
#pragma mark 开始下载
-(void)startDownload{
    if(self.ipaModel && self.downloadType == DownloadTypeDownloading){
        [self.tableView.zxDatas addObject:self.downloadingModel];;
    }
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

@end
