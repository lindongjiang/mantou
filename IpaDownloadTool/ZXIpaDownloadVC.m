//
//  ZXIpaDownloadVC.m
//  IpaDownloadTool
//
//  Created on 2024/7/13.
//  Copyright © 2024. All rights reserved.
//

#import "ZXIpaDownloadVC.h"
#import "ZXIpaGetVC.h"
#import "ZXLocalIpaVC.h"
#import "ZXIpaHisVC.h"
#import "SGQRCodeScanningVC.h"
#import "ZXIpaUrlHisVC.h"
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, ZXIpaDownloadTabType) {
    ZXIpaDownloadTabTypeGet = 0,    // IPA提取器
    ZXIpaDownloadTabTypeDownload,   // 下载中/已下载
    ZXIpaDownloadTabTypeHistory     // 历史记录
};

@interface ZXIpaDownloadVC () <UIScrollViewDelegate>

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *containerScrollView;
@property (nonatomic, strong) ZXIpaGetVC *ipaGetVC;
@property (nonatomic, strong) ZXLocalIpaVC *localIpaVC;
@property (nonatomic, strong) ZXIpaHisVC *ipaHisVC;
@property (nonatomic, assign) ZXIpaDownloadTabType currentTabType;

@end

@implementation ZXIpaDownloadVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IPA下载";
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self setupUI];
    [self setupChildViewControllers];
    [self setupNavigationItems];
    
    // 默认选中第一个标签
    self.currentTabType = ZXIpaDownloadTabTypeGet;
    [self.segmentedControl setSelectedSegmentIndex:self.currentTabType];
    [self scrollToTabType:self.currentTabType animated:NO];
}

- (void)setupUI {
    // 创建分段控制器
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"IPA提取器", @"下载管理", @"历史记录"]];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.segmentedControl addTarget:self action:@selector(segmentedControlValueChanged:) forControlEvents:UIControlEventValueChanged];
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.tintColor = MainColor;
    [self.view addSubview:self.segmentedControl];
    
    // 创建容器滚动视图
    self.containerScrollView = [[UIScrollView alloc] init];
    self.containerScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerScrollView.pagingEnabled = YES;
    self.containerScrollView.showsHorizontalScrollIndicator = NO;
    self.containerScrollView.delegate = self;
    self.containerScrollView.bounces = NO;
    [self.view addSubview:self.containerScrollView];
    
    // 设置约束
    CGFloat topMargin = 10;
    CGFloat sideMargin = 20;
    
    // 分段控制器约束
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topMargin],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:sideMargin],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-sideMargin],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // 容器滚动视图约束
    [NSLayoutConstraint activateConstraints:@[
        [self.containerScrollView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:topMargin],
        [self.containerScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.containerScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.containerScrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupNavigationItems {
    // 添加左侧的+按钮
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
                                                                             target:self 
                                                                             action:@selector(addItemAction)];
    self.navigationItem.leftBarButtonItem = addItem;
    
    // 添加右侧的网址和二维码按钮
    UIButton *inputBtn = [[UIButton alloc] init];
    [inputBtn addTarget:self action:@selector(inputAction) forControlEvents:UIControlEventTouchUpInside];
    [inputBtn setTitleColor:MainColor forState:UIControlStateNormal];
    inputBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [inputBtn setTitle:@"网址" forState:UIControlStateNormal];
    UILongPressGestureRecognizer *inputLongPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(inputLongPress:)];
    [inputBtn addGestureRecognizer:inputLongPressGestureRecognizer];
    UIBarButtonItem *inputItem = [[UIBarButtonItem alloc] initWithCustomView:inputBtn];
    
    UIBarButtonItem *qrcodeItem = [[UIBarButtonItem alloc] initWithTitle:@"二维码" 
                                                                   style:UIBarButtonItemStyleDone 
                                                                  target:self 
                                                                  action:@selector(qrcodeItemAction)];
    
    self.navigationItem.rightBarButtonItems = @[inputItem, qrcodeItem];
}

- (void)setupChildViewControllers {
    // 创建子视图控制器
    self.ipaGetVC = [[ZXIpaGetVC alloc] init];
    self.localIpaVC = [[ZXLocalIpaVC alloc] init];
    self.ipaHisVC = [[ZXIpaHisVC alloc] init];
    
    // 添加子视图控制器
    [self addChildViewController:self.ipaGetVC];
    [self addChildViewController:self.localIpaVC];
    [self addChildViewController:self.ipaHisVC];
    
    // 设置容器滚动视图的内容大小
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height - self.segmentedControl.frame.size.height - 20;
    self.containerScrollView.contentSize = CGSizeMake(width * 3, height);
    
    // 添加子视图控制器的视图到容器滚动视图
    self.ipaGetVC.view.frame = CGRectMake(0, 0, width, height);
    self.localIpaVC.view.frame = CGRectMake(width, 0, width, height);
    self.ipaHisVC.view.frame = CGRectMake(width * 2, 0, width, height);
    
    [self.containerScrollView addSubview:self.ipaGetVC.view];
    [self.containerScrollView addSubview:self.localIpaVC.view];
    [self.containerScrollView addSubview:self.ipaHisVC.view];
    
    // 完成子视图控制器的添加
    [self.ipaGetVC didMoveToParentViewController:self];
    [self.localIpaVC didMoveToParentViewController:self];
    [self.ipaHisVC didMoveToParentViewController:self];
}

#pragma mark - Actions

- (void)segmentedControlValueChanged:(UISegmentedControl *)sender {
    self.currentTabType = (ZXIpaDownloadTabType)sender.selectedSegmentIndex;
    [self scrollToTabType:self.currentTabType animated:YES];
}

- (void)scrollToTabType:(ZXIpaDownloadTabType)tabType animated:(BOOL)animated {
    CGFloat width = self.view.bounds.size.width;
    CGPoint offset = CGPointMake(width * tabType, 0);
    [self.containerScrollView setContentOffset:offset animated:animated];
}

#pragma mark - 导航栏按钮操作

// 点击了+按钮
- (void)addItemAction {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择操作"
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *scanAction = [UIAlertAction actionWithTitle:@"扫描二维码"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        [self qrcodeItemAction];
    }];
    
    UIAlertAction *inputAction = [UIAlertAction actionWithTitle:@"输入网址"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        [self inputAction];
    }];
    
    UIAlertAction *historyAction = [UIAlertAction actionWithTitle:@"网址历史"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
        [self showUrlHistory];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alertController addThemeAction:scanAction];
    [alertController addThemeAction:inputAction];
    [alertController addThemeAction:historyAction];
    [alertController addThemeAction:cancelAction];
    
    // 在iPad上需要设置弹出位置
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

// 点击了二维码
- (void)qrcodeItemAction {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [ALToastView showToastWithText:@"摄像头不可用"];
        return;
    }
    SGQRCodeScanningVC *VC = [[SGQRCodeScanningVC alloc] init];
    VC.resultBlock = ^(NSString *resultStr) {
        [self.ipaGetVC handelWithUrlStr:resultStr];
    };
    [self.navigationController pushViewController:VC animated:YES];
}

// 点击了网址
- (void)inputAction {
    [self.ipaGetVC handleInputUrlFrom:0]; // InputUrlFromInput
}

// 长按了网址
- (void)inputLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    [self showUrlHistory];
}

// 显示URL历史
- (void)showUrlHistory {
    ZXIpaUrlHisVC *VC = [[ZXIpaUrlHisVC alloc] init];
    VC.urlSelectedBlock = ^(NSString * _Nonnull urlStr) {
        [self.ipaGetVC handelWithUrlStr:urlStr];
    };
    [self.navigationController pushViewController:VC animated:YES];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.containerScrollView) {
        CGFloat pageWidth = scrollView.frame.size.width;
        NSInteger page = scrollView.contentOffset.x / pageWidth;
        self.currentTabType = (ZXIpaDownloadTabType)page;
        [self.segmentedControl setSelectedSegmentIndex:self.currentTabType];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    // 更新容器滚动视图的内容大小和子视图的位置
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height - self.segmentedControl.frame.origin.y - self.segmentedControl.frame.size.height - 10;
    
    self.containerScrollView.contentSize = CGSizeMake(width * 3, height);
    
    self.ipaGetVC.view.frame = CGRectMake(0, 0, width, height);
    self.localIpaVC.view.frame = CGRectMake(width, 0, width, height);
    self.ipaHisVC.view.frame = CGRectMake(width * 2, 0, width, height);
    
    // 保持当前页面的位置
    [self scrollToTabType:self.currentTabType animated:NO];
}

@end 