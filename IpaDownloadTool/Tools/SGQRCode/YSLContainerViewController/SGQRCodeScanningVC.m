//
//  SGQRCodeScanningVC.m
//  SGQRCodeExample
//
//  Created by kingsic on 17/3/20.
//  Copyright © 2017年 kingsic. All rights reserved.
//

#import "SGQRCodeScanningVC.h"
#import "SGQRCode.h"
#import "ScanSuccessJumpVC.h"
@interface SGQRCodeScanningVC () <SGQRCodeScanManagerDelegate, SGQRCodeAlbumManagerDelegate>
@property (nonatomic, strong) SGQRCodeScanningView *scanningView;
@end

@implementation SGQRCodeScanningVC

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.scanningView addTimer];
    
    self.navigationController.interactivePopGestureRecognizer.delegate = (id)self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.scanningView removeTimer];
    
}

- (void)dealloc {
    NSLog(@"SGQRCodeScanningVC - dealloc");
    [self removeScanningView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.view.backgroundColor = [UIColor clearColor];
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    [self.view addSubview:self.scanningView];
    [self setupNavigationBar];
    [self setupQRCodeScanning];
}

- (SGQRCodeScanningView *)scanningView {
    if (!_scanningView) {
        _scanningView = [SGQRCodeScanningView scanningViewWithFrame:self.view.bounds layer:self.view.layer];
    }
    return _scanningView;
}
- (void)removeScanningView {
    [self.scanningView removeTimer];
    [self.scanningView removeFromSuperview];
    self.scanningView = nil;
}

- (void)setupNavigationBar {
    self.title = @"扫描二维码";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"相册" style:(UIBarButtonItemStyleDone) target:self action:@selector(rightBarButtonItenAction)];
}

- (void)rightBarButtonItenAction {
    SGQRCodeAlbumManager *manager = [SGQRCodeAlbumManager sharedManager];
    [manager SG_readQRCodeFromAlbumWithCurrentController:self];
    manager.delegate = self;
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    // 栅栏函数
    dispatch_barrier_async(queue, ^{
        BOOL isPHAuthorization = manager.isPHAuthorization;
        if (isPHAuthorization == YES) {
            [self removeScanningView];
        }
    });
}

- (void)setupQRCodeScanning {
    SGQRCodeScanManager *manager = [SGQRCodeScanManager sharedManager];
    NSArray *arr = @[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeCode128Code];
    // AVCaptureSessionPreset1920x1080 推荐使用，对于小型的二维码读取率较高
    [manager SG_setupSessionPreset:AVCaptureSessionPreset1920x1080 metadataObjectTypes:arr currentController:self];
    manager.delegate = self;
}

#pragma mark - - - SGQRCodeAlbumManagerDelegate
- (void)QRCodeAlbumManagerDidCancelWithImagePickerController:(SGQRCodeAlbumManager *)albumManager {
    [self.view addSubview:self.scanningView];
}
- (void)QRCodeAlbumManager:(SGQRCodeAlbumManager *)albumManager didFinishPickingMediaWithResult:(NSString *)result {
    __weak __typeof(self) weakSelf = self;
    if(self.resultBlock){
        weakSelf.resultBlock(result);
        [weakSelf.navigationController popViewControllerAnimated:YES];
        return;
    }
    
    if ([result hasPrefix:@"http"]) {
         NSLog(@"QRCodeAlbumManager111");
        
        ScanSuccessJumpVC *jumpVC = [[ScanSuccessJumpVC alloc] init];
        jumpVC.jump_URL = result;
        [self.navigationController pushViewController:jumpVC animated:YES];
        
    } else {
         NSLog(@"QRCodeAlbumManager222");
        ScanSuccessJumpVC *jumpVC = [[ScanSuccessJumpVC alloc] init];
        jumpVC.jump_bar_code = result;
        [self.navigationController pushViewController:jumpVC animated:YES];
    }
}

#pragma mark - - - SGQRCodeScanManagerDelegate
- (void)QRCodeScanManager:(SGQRCodeScanManager *)scanManager didOutputMetadataObjects:(NSArray *)metadataObjects {
    NSLog(@"metadataObjects - - %@", metadataObjects);
    if (metadataObjects != nil && metadataObjects.count > 0) {
        [scanManager SG_palySoundName:@"SGQRCode.bundle/sound.caf"];
        [scanManager SG_stopRunning];
        [scanManager SG_videoPreviewLayerRemoveFromSuperlayer];
        
        AVMetadataMachineReadableCodeObject *obj = metadataObjects[0];
        if(self.resultBlock){
            self.resultBlock([obj stringValue]);
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }
        if ([[obj stringValue] hasPrefix:@"http"]) {
           
            ScanSuccessJumpVC *jumpVC = [[ScanSuccessJumpVC alloc] init];
            jumpVC.jump_URL = [obj stringValue];
            [self.navigationController pushViewController:jumpVC animated:YES];
            
        } else {
           
            ScanSuccessJumpVC *jumpVC = [[ScanSuccessJumpVC alloc] init];
            jumpVC.jump_bar_code = [obj stringValue];
            [self.navigationController pushViewController:jumpVC animated:YES];
        }
       
    } else {
        UIAlertController *alertC = [UIAlertController alertControllerWithTitle:@"提示" message:@"未识别到二维码!" preferredStyle:(UIAlertControllerStyleAlert)];
        UIAlertAction *alertA = [UIAlertAction actionWithTitle:@"好" style:(UIAlertActionStyleDefault) handler:^(UIAlertAction * _Nonnull action) {
            
        }];
           [alertC addAction:alertA];
            [self presentViewController:alertC animated:YES completion:nil];
    }
}

-(UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}

@end

