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
#import "NSString+ZXMD5.h"
#import "ZXIpaHttpRequest.h"

typedef NS_ENUM(NSInteger, ZXIpaDownloadTabType) {
    ZXIpaDownloadTabTypeDownload = 0,   // 下载中/已下载
    ZXIpaDownloadTabTypeHistory         // 历史记录
};

// 处理url键入来源
typedef enum {
    InputUrlFromInput = 0x00,    // url键入来源于用户输入
    InputUrlFromEdit = 0x01,    // url键入来源于用户编辑
} InputUrlFrom;

@interface ZXIpaDownloadVC () <UIScrollViewDelegate, WKNavigationDelegate>

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *containerScrollView;
@property (nonatomic, strong) ZXLocalIpaVC *localIpaVC;
@property (nonatomic, strong) ZXIpaHisVC *ipaHisVC;
@property (nonatomic, assign) ZXIpaDownloadTabType currentTabType;
@property (nonatomic, copy) NSString *currentUrlStr; // 当前URL字符串
@property (nonatomic, strong) WKWebView *hiddenWebView; // 添加隐藏的WebView属性
@property (nonatomic, copy) NSString *ignoredIpaDownloadUrl; // 忽略的IPA下载URL

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
    self.currentTabType = ZXIpaDownloadTabTypeDownload;
    [self.segmentedControl setSelectedSegmentIndex:self.currentTabType];
    [self scrollToTabType:self.currentTabType animated:NO];
}

- (void)setupUI {
    // 创建分段控制器
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"下载管理", @"历史记录"]];
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
    // 添加右侧的+按钮
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
                                                                             target:self 
                                                                             action:@selector(addItemAction)];
    self.navigationItem.rightBarButtonItem = addItem;
    
    // 移除左侧按钮
    self.navigationItem.leftBarButtonItem = nil;
}

- (void)setupChildViewControllers {
    // 移除IPA提取器，只保留下载管理和历史记录
    
    // 创建下载管理视图控制器
    self.localIpaVC = [[ZXLocalIpaVC alloc] init];
    [self addChildViewController:self.localIpaVC];
    
    // 创建历史记录视图控制器
    self.ipaHisVC = [[ZXIpaHisVC alloc] init];
    [self addChildViewController:self.ipaHisVC];
    
    // 设置容器滚动视图的内容
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    self.containerScrollView.contentSize = CGSizeMake(screenWidth * 2, 0);
    
    // 添加子视图控制器的视图到容器滚动视图
    self.localIpaVC.view.frame = CGRectMake(0, 0, screenWidth, self.containerScrollView.frame.size.height);
    self.ipaHisVC.view.frame = CGRectMake(screenWidth, 0, screenWidth, self.containerScrollView.frame.size.height);
    
    [self.containerScrollView addSubview:self.localIpaVC.view];
    [self.containerScrollView addSubview:self.ipaHisVC.view];
    
    [self.localIpaVC didMoveToParentViewController:self];
    [self.ipaHisVC didMoveToParentViewController:self];
}

#pragma mark - Actions

- (void)segmentedControlValueChanged:(UISegmentedControl *)sender {
    // 更新当前标签类型
    self.currentTabType = sender.selectedSegmentIndex;
    
    // 滚动到相应的标签页
    [self scrollToTabType:self.currentTabType animated:YES];
}

- (void)scrollToTabType:(ZXIpaDownloadTabType)tabType animated:(BOOL)animated {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGPoint offset = CGPointMake(screenWidth * tabType, 0);
    [self.containerScrollView setContentOffset:offset animated:animated];
}

#pragma mark - 按钮事件

- (void)addItemAction {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"选择操作"
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 添加"输入链接"选项
    UIAlertAction *inputUrlAction = [UIAlertAction actionWithTitle:@"输入链接"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [self handleInputUrlFrom:InputUrlFromInput];
    }];
    
    // 添加"扫描二维码"选项
    UIAlertAction *scanQRCodeAction = [UIAlertAction actionWithTitle:@"扫描二维码"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction * _Nonnull action) {
        [self scanQRCode];
    }];
    
    // 添加"取消"选项
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alertController addAction:inputUrlAction];
    [alertController addAction:scanQRCodeAction];
    [alertController addAction:cancelAction];
    
    // 在iPad上需要设置弹出位置
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - 辅助方法

- (void)handleInputUrlFrom:(InputUrlFrom)from {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"输入链接"
                                                                             message:@"请输入应用下载链接"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"https://";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        
        if (from == InputUrlFromEdit) {
            textField.text = self.currentUrlStr;
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull action) {
        NSString *urlStr = alertController.textFields.firstObject.text;
        if (urlStr && urlStr.length > 0) {
            // 直接处理URL，不再跳转到ZXIpaGetVC
            [self processUrlForDownload:urlStr];
        } else {
            [ALToastView showToastWithText:@"请输入有效的URL"];
        }
    }];
    
    [alertController addAction:cancelAction];
    [alertController addAction:confirmAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

// 新增方法：处理URL并添加到下载管理
- (void)processUrlForDownload:(NSString *)urlStr {
    // 检查URL是否为空
    if (!urlStr || [urlStr length] == 0) {
        NSLog(@"[下载] 错误: URL为空");
        [ALToastView showToastWithText:@"URL不能为空"];
        return;
    }
    
    // 清理WebView缓存
    NSSet *websiteDataTypes = [NSSet setWithArray:@[
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeOfflineWebApplicationCache,
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeWebSQLDatabases,
        WKWebsiteDataTypeIndexedDBDatabases
    ]];
    
    NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
        NSLog(@"已清理WebView缓存");
    }];
    
    // 确保URL格式正确
    if(![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"] && ![urlStr hasPrefix:@"itms-services://"]) {
        urlStr = [@"http://" stringByAppendingString:urlStr];
    }
    
    // 显示加载指示器
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.label.text = @"正在解析链接...";
    
    // 检查是否是直接的IPA下载链接
    if ([[urlStr pathExtension] isEqualToString:@"ipa"] || [urlStr containsString:@".ipa&"]) {
        [self handleDirectIpaDownload:urlStr];
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        return;
    }
    
    // 检查是否是itms-services链接
    if ([urlStr hasPrefix:@"itms-services://"] || [urlStr containsString:@"itemService="]) {
        NSString *plistUrl = [urlStr getPlistPathUrlStr];
        if (plistUrl) {
            [self downloadPlistAndExtractIpa:plistUrl];
        } else {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [ALToastView showToastWithText:@"无法解析plist链接"];
        }
        return;
    }
    
    // 如果不是直接的IPA链接，使用WebView加载页面
    // 移除旧的隐藏WebView（如果存在）
    if (self.hiddenWebView) {
        [self.hiddenWebView removeFromSuperview];
        self.hiddenWebView = nil;
    }
    
    // 创建新的WebView配置
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore]; // 使用非持久化数据存储
    
    // 创建新的隐藏WebView
    self.hiddenWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.hiddenWebView.navigationDelegate = self;
    self.hiddenWebView.hidden = YES;
    [self.view addSubview:self.hiddenWebView];
    
    // 保存当前URL以便后续使用
    self.currentUrlStr = urlStr;
    
    // 加载URL
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        // 尝试URL编码
        NSString *encodedUrlStr = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        url = [NSURL URLWithString:encodedUrlStr];
        
        if (!url) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [ALToastView showToastWithText:@"无效的URL格式"];
            return;
        }
    }
    
    // 创建一个不使用缓存的请求
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    [self.hiddenWebView loadRequest:request];
    
    // 设置超时处理
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (hud.superview) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [ALToastView showToastWithText:@"链接解析超时，请重试或直接输入IPA下载链接"];
            [self.hiddenWebView removeFromSuperview];
            self.hiddenWebView = nil;
        }
    });
}

// 处理直接的IPA下载链接
- (void)handleDirectIpaDownload:(NSString *)urlStr {
    if (!urlStr || [urlStr length] == 0) {
        NSLog(@"[下载] 错误: 下载URL为空");
        [ALToastView showToastWithText:@"下载链接无效"];
        return;
    }
    
    ZXIpaModel *ipaModel = [[ZXIpaModel alloc] init];
    
    // 安全地设置title，避免解码失败导致nil
    NSString *decodedTitle = nil;
    @try {
        decodedTitle = [[[urlStr lastPathComponent] stringByDeletingPathExtension] stringByRemovingPercentEncoding];
    } @catch (NSException *exception) {
        NSLog(@"[解码] 解码URL失败: %@", exception.reason);
        decodedTitle = nil;
    }
    
    if (!decodedTitle || [decodedTitle length] == 0) {
        // 如果解码失败，尝试直接使用未解码的路径
        decodedTitle = [[urlStr lastPathComponent] stringByDeletingPathExtension];
        if (!decodedTitle || [decodedTitle length] == 0) {
            decodedTitle = @"未知应用";
        }
    }
    
    // 确保title不为nil
    ipaModel.title = decodedTitle ?: @"未知应用";
    ipaModel.downloadUrl = urlStr;
    ipaModel.sign = [ipaModel.downloadUrl md5Str];
    
    // 设置本地保存路径
    NSString *fileName = [NSString stringWithFormat:@"%@.ipa", ipaModel.title];
    ipaModel.localPath = [ZXIpaDownloadedPath stringByAppendingPathComponent:fileName];
    
    // 添加到下载管理
    [self addIpaToDownloadManager:ipaModel];
    
    // 切换到下载管理标签
    self.currentTabType = ZXIpaDownloadTabTypeDownload;
    [self.segmentedControl setSelectedSegmentIndex:self.currentTabType];
    [self scrollToTabType:self.currentTabType animated:YES];
    
    // 直接启动下载
    [self startDownloadIpa:ipaModel];
    
    [ALToastView showToastWithText:@"已添加到下载队列"];
}

// 新增方法：启动IPA下载
- (void)startDownloadIpa:(ZXIpaModel *)ipaModel {
    // 确保本地IPA视图控制器存在
    if (!self.localIpaVC) {
        NSLog(@"[下载] 本地IPA视图控制器不存在");
        return;
    }
    
    // 调用本地IPA视图控制器的下载方法
    if ([self.localIpaVC respondsToSelector:@selector(startDownloadWithIpaModel:)]) {
        NSLog(@"[下载] 开始下载IPA: %@", ipaModel.title);
        [self.localIpaVC performSelector:@selector(startDownloadWithIpaModel:) withObject:ipaModel];
    } else {
        NSLog(@"[下载] 本地IPA视图控制器不支持startDownloadWithIpaModel:方法");
        // 尝试使用旧的方法
        if ([self.localIpaVC respondsToSelector:@selector(setIpaModel:)]) {
            NSLog(@"[下载] 使用setIpaModel:方法设置下载模型");
            [self.localIpaVC performSelector:@selector(setIpaModel:) withObject:ipaModel];
        }
    }
}

// 下载plist文件并提取IPA信息
- (void)downloadPlistAndExtractIpa:(NSString *)plistUrl {
    [ZXIpaHttpRequest downLoadWithUrlStr:plistUrl path:ZXPlistCachePath callBack:^(BOOL result, id _Nonnull data) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            
            if (result) {
                NSDictionary *plistDic = [[NSDictionary alloc] initWithContentsOfFile:data];
                ZXIpaModel *ipaModel = [[ZXIpaModel alloc] initWithDic:plistDic];
                
                if (ipaModel) {
                    // 确保title不为nil
                    if (!ipaModel.title || [ipaModel.title length] == 0) {
                        ipaModel.title = @"未知应用";
                    }
                    
                    // 设置本地保存路径
                    NSString *fileName = [NSString stringWithFormat:@"%@.ipa", ipaModel.title];
                    ipaModel.localPath = [ZXIpaDownloadedPath stringByAppendingPathComponent:fileName];
                    
                    // 添加到下载管理
                    [self addIpaToDownloadManager:ipaModel];
                    
                    // 切换到下载管理标签
                    self.currentTabType = ZXIpaDownloadTabTypeDownload;
                    [self.segmentedControl setSelectedSegmentIndex:self.currentTabType];
                    [self scrollToTabType:self.currentTabType animated:YES];
                    
                    // 直接启动下载
                    [self startDownloadIpa:ipaModel];
                    
                    [ALToastView showToastWithText:[NSString stringWithFormat:@"已添加「%@」到下载队列", ipaModel.title]];
                } else {
                    [ALToastView showToastWithText:@"无法解析plist文件"];
                }
            } else {
                [ALToastView showToastWithText:[NSString stringWithFormat:@"plist文件下载失败: %@", ((NSError *)data).localizedDescription]];
            }
        });
    }];
}

// 添加IPA到下载管理
- (void)addIpaToDownloadManager:(ZXIpaModel *)ipaModel {
    // 确保title不为nil
    if (!ipaModel.title || [ipaModel.title length] == 0) {
        ipaModel.title = @"未知应用";
    }
    
    // 保存IPA模型到数据库
    NSArray *sameArr = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
    ipaModel.localPath = [sameArr.firstObject valueForKey:@"localPath"];
    
    if (sameArr.count) {
        [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'", ipaModel.sign]];
    }
    
    ipaModel.fromPageUrl = self.currentUrlStr;
    NSDate *date = [NSDate date];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    ipaModel.time = [format stringFromDate:date];
    [ipaModel zx_dbSave];
    
    // 通知本地IPA视图控制器刷新数据
    if (self.localIpaVC && [self.localIpaVC respondsToSelector:@selector(refreshData)]) {
        [self.localIpaVC performSelector:@selector(refreshData)];
    }
}

// 修改扫描二维码方法
- (void)scanQRCode {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [ALToastView showToastWithText:@"摄像头不可用"];
        return;
    }
    
    SGQRCodeScanningVC *scanVC = [[SGQRCodeScanningVC alloc] init];
    scanVC.resultBlock = ^(NSString *resultStr) {
        // 检查扫描结果是否有效
        if (resultStr && [resultStr length] > 0) {
            // 直接处理扫描结果，不再跳转到ZXIpaGetVC
            [self processUrlForDownload:resultStr];
        } else {
            [ALToastView showToastWithText:@"扫描结果无效"];
        }
    };
    
    [self.navigationController pushViewController:scanVC animated:YES];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat pageWidth = scrollView.frame.size.width;
    NSInteger page = scrollView.contentOffset.x / pageWidth;
    
    // 更新分段控制器的选中状态
    self.segmentedControl.selectedSegmentIndex = page;
    self.currentTabType = page;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    // 更新容器滚动视图的内容大小和子视图的位置
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height - self.segmentedControl.frame.origin.y - self.segmentedControl.frame.size.height - 10;
    
    self.containerScrollView.contentSize = CGSizeMake(width * 2, height);
    
    self.localIpaVC.view.frame = CGRectMake(0, 0, width, height);
    self.ipaHisVC.view.frame = CGRectMake(width, 0, width, height);
    
    // 保持当前页面的位置
    [self scrollToTabType:self.currentTabType animated:NO];
}

#pragma mark - WKNavigationDelegate

// 网页将要开始加载
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *urlStr = navigationAction.request.URL.absoluteString;
    NSLog(@"[WebView] 将要加载URL: %@", urlStr);
    
    // 检查是否是IPA下载链接
    if ([[urlStr pathExtension] isEqualToString:@"ipa"] || [urlStr containsString:@".ipa&"]) {
        NSLog(@"[WebView] 检测到IPA下载链接");
        if (!(self.ignoredIpaDownloadUrl && [self.ignoredIpaDownloadUrl isEqualToString:urlStr])) {
            // 处理IPA下载链接
            [self handleDirectIpaDownload:urlStr];
            decisionHandler(WKNavigationActionPolicyCancel);
            
            // 移除隐藏的WebView
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [webView removeFromSuperview];
            self.hiddenWebView = nil;
            
            return;
        } else {
            self.ignoredIpaDownloadUrl = nil;
        }
    }
    
    // 检查是否是itms-services链接
    if ([urlStr hasPrefix:@"itms-services://"] || [urlStr containsString:@"itemService="]) {
        NSLog(@"[WebView] 检测到itms-services链接");
        NSString *plistUrl = [urlStr getPlistPathUrlStr];
        if (plistUrl) {
            NSLog(@"[WebView] 提取到plist URL: %@", plistUrl);
            [self downloadPlistAndExtractIpa:plistUrl];
            
            // 移除隐藏的WebView
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [webView removeFromSuperview];
            self.hiddenWebView = nil;
            
            if (![urlStr containsString:@"itemService="]) {
                decisionHandler(WKNavigationActionPolicyCancel);
                return;
            }
        } else {
            NSLog(@"[WebView] 无法从itms-services链接提取plist URL");
        }
    }
    
    // 检查是否是重定向
    if (navigationAction.navigationType == WKNavigationTypeOther && 
        ![urlStr isEqualToString:self.currentUrlStr] && 
        ![urlStr containsString:@"about:blank"]) {
        NSLog(@"[WebView] 检测到重定向: %@ -> %@", self.currentUrlStr, urlStr);
        self.currentUrlStr = urlStr;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
}

// 网页加载完成
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // 网页加载完成后，隐藏加载指示器
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    
    // 获取网页标题
    [webView evaluateJavaScript:@"document.title" completionHandler:^(id _Nullable title, NSError * _Nullable error) {
        if (title && [title isKindOfClass:[NSString class]] && [(NSString *)title length] > 0) {
            NSLog(@"[WebView] 页面加载完成，标题: %@", title);
            [ALToastView showToastWithText:[NSString stringWithFormat:@"已加载: %@", title]];
            
            // 尝试查找页面中的IPA下载链接
            [webView evaluateJavaScript:@"Array.from(document.querySelectorAll('a')).filter(a => a.href.endsWith('.ipa') || a.href.includes('.ipa&')).map(a => a.href)" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
                if (result && [result isKindOfClass:[NSArray class]] && [result count] > 0) {
                    NSArray *ipaLinks = (NSArray *)result;
                    NSLog(@"[WebView] 在页面中找到IPA下载链接: %@", ipaLinks);
                    
                    // 处理第一个IPA链接
                    NSString *firstIpaLink = ipaLinks[0];
                    if (firstIpaLink && [firstIpaLink length] > 0) {
                        [self handleDirectIpaDownload:firstIpaLink];
                        
                        // 移除隐藏的WebView
                        [webView removeFromSuperview];
                        self.hiddenWebView = nil;
                    }
                } else {
                    NSLog(@"[WebView] 页面中未找到IPA下载链接");
                }
            }];
        } else {
            NSLog(@"[WebView] 页面加载完成，但标题为空或无效");
            [ALToastView showToastWithText:@"页面已加载"];
        }
    }];
}

// 网页加载失败
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    
    NSString *errInfo = error.localizedDescription;
    NSLog(@"[WebView] 页面加载失败: %@, 错误码: %ld", errInfo, (long)error.code);
    
    if (errInfo && ![errInfo isEqualToString:@"Frame load interrupted"]) {
        [ALToastView showToastWithText:[NSString stringWithFormat:@"加载失败: %@", errInfo]];
    }
    
    // 移除隐藏的WebView
    [webView removeFromSuperview];
    self.hiddenWebView = nil;
}

// 网页加载失败
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    
    NSString *errInfo = error.localizedDescription;
    NSLog(@"[WebView] 页面预加载失败: %@, 错误码: %ld", errInfo, (long)error.code);
    
    if (errInfo && ![errInfo isEqualToString:@"Frame load interrupted"]) {
        [ALToastView showToastWithText:[NSString stringWithFormat:@"加载失败: %@", errInfo]];
    }
    
    // 移除隐藏的WebView
    [webView removeFromSuperview];
    self.hiddenWebView = nil;
}

@end 