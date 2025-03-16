//
//  ZXIpaGetVC.m
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/28.
//  Copyright © 2019 李兆祥. All rights reserved.
//  https://github.com/SmileZXLee/IpaDownloadTool

#import <WebKit/WebKit.h>
#import "ZXIpaGetVC.h"
#import "ZXIpaUrlHisModel.h"
#import "ZXIpaHttpRequest.h"
#import "ZXIpaModel.h"
#import "SGQRCodeScanningVC.h"
#import "TCMobileProvision.h"
#import "NSString+ZXMD5.h"
#import "ZXDeviceInfo.h"
#import "AFNetworkReachabilityManager.h"

#import "ZXIpaHisVC.h"
#import "ZXIpaDetailVC.h"
#import "ZXLocalIpaVC.h"
#import "ZXIpaUrlHisVC.h"
#import "ZXIpaAboutVC.h"

// 处理url键入来源
typedef enum {
    InputUrlFromInput = 0x00,    // url键入来源于用户输入
    InputUrlFromEdit = 0x01,    // url键入来源于用户编辑
}InputUrlFrom;

@interface ZXIpaGetVC ()<WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate, NSURLSessionDelegate>
@property (weak, nonatomic) IBOutlet WKWebView *webView;
@property (weak, nonatomic) IBOutlet UIButton *webBackBtn;
@property (weak, nonatomic) IBOutlet UIButton *webNextBtn;
@property (weak, nonatomic) IBOutlet UIButton *webReloadBtn;
@property (weak, nonatomic) IBOutlet UIButton *aboutBtn;

@property (weak, nonatomic) IBOutlet UITextField *webTitleTf;

@property (weak, nonatomic)CALayer *progressLayer;
@property (copy, nonatomic)NSString *urlStr;
@property (copy, nonatomic)NSString *currentUrlStr;
@property (assign, nonatomic)BOOL urlStartHandled;
@property (assign, nonatomic)BOOL isDeveloperMode;
@property (copy, nonatomic)NSString *ignoredIpaDownloadUrl;
@property (strong, nonatomic)NSArray *mobileprovisionRegulaArr;
@end

@implementation ZXIpaGetVC

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 检查IBOutlet是否已连接
    if (!self.webView) {
        NSLog(@"[错误] webView未连接，请检查IBOutlet连接");
    }
    
    if([[NSUserDefaults standardUserDefaults]objectForKey:@"userAgreementAgreed"]){
        [self initUI];
    }else{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"用户协议&使用说明" message:[NSString stringWithFormat:@"%@\n\n点击同意即代表您已阅读协议并同意协议中包含的条款",ZXUserAgreement] preferredStyle:UIAlertControllerStyleAlert];
        UILabel *messageLabel = [alertController.view valueForKeyPath:@"_messageLabel"];
        if(messageLabel){
            messageLabel.textAlignment = NSTextAlignmentLeft;
        }
        UIAlertAction *agreeAction = [UIAlertAction actionWithTitle:@"同意" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setObject:@1 forKey:@"userAgreementAgreed"];
            [self initUI];
        }];
        UIAlertAction *rejectAction = [UIAlertAction actionWithTitle:@"不同意" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }];
        [alertController addThemeAction:agreeAction];
        [alertController addThemeAction:rejectAction];
        [self presentViewController:alertController animated:YES completion:nil];
    }
    self.isDeveloperMode = [[NSUserDefaults standardUserDefaults]objectForKey:@"developerMode"] != nil;
    
    // 适应底部TabBar
    if (self.tabBarController) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
}

-(void)viewWillLayoutSubviews{
    [super viewWillLayoutSubviews];
    
    // 调整WebView的高度以适应TabBar
    if (self.tabBarController && self.webView) {
        CGFloat tabBarHeight = self.tabBarController.tabBar.frame.size.height;
        UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, tabBarHeight, 0);
        self.webView.scrollView.contentInset = insets;
        self.webView.scrollView.scrollIndicatorInsets = insets;
    }
}

- (void)dealloc{
    @try {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    } @catch (NSException *exception) {
        NSLog(@"[警告] 移除KVO观察者失败: %@", exception.reason);
    }
    
    // 停止网络监听
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:nil];
    [[AFNetworkReachabilityManager sharedManager] stopMonitoring];
}

#pragma mark - 初始化视图
-(void)initUI{
    self.view.backgroundColor = [UIColor whiteColor];
    self.webReloadBtn.enabled = NO;
    self.webBackBtn.enabled = NO;
    self.webNextBtn.enabled = NO;
    [self.webReloadBtn setTintColor:MainColor];
    [self.webBackBtn setTintColor:MainColor];
    [self.webNextBtn setTintColor:MainColor];
    [self.aboutBtn setTintColor:MainColor];
    [self.webTitleTf setTintColor:MainColor];
    [self.webTitleTf setTextColor:MainColor];
    self.webTitleTf.adjustsFontSizeToFitWidth = YES;
    [self.webTitleTf addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(webTitleTap)]];
    self.webTitleTf.delegate = self;
    self.navigationController.navigationBar.translucent = NO;
    self.title = MainTitle;
    
    UIButton *inputBtn = [[UIButton alloc]init];
    [inputBtn addTarget:self action:@selector(inputAction) forControlEvents:UIControlEventTouchUpInside];
    [inputBtn setTitleColor:MainColor forState:UIControlStateNormal];
    inputBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [inputBtn setTitle:@"网址" forState:UIControlStateNormal];
    UILongPressGestureRecognizer *inputLongPressGestureRecognizer = [[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(inputLongPress:)];
    [inputBtn addGestureRecognizer:inputLongPressGestureRecognizer];
    UIBarButtonItem *inputItem = [[UIBarButtonItem alloc]initWithCustomView:inputBtn];
    UIBarButtonItem *qrcodeItem = [[UIBarButtonItem alloc]initWithTitle:@"二维码" style:UIBarButtonItemStyleDone target:self action:@selector(qrcodeItemAction)];
    self.navigationItem.rightBarButtonItems = @[inputItem,qrcodeItem];
    
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.backgroundColor = [UIColor clearColor];
    self.webView.opaque = NO;
    self.webView.customUserAgent = ZXWebUA;
    [self.webView setAllowsBackForwardNavigationGestures:true];
    [self initWebViewProgressView];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(pasteboardStrLoadUrl:) name:ZXPasteboardStrLoadUrlNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(updateMobileprovisionRegulaArr) name:ZXMobileprovisionRegularUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(updateDeveloperMode) name:ZXDeveloperModeUpdateNotification object:nil];
    
    if (@available(iOS 15.0, *)) {
       UINavigationBarAppearance *appperance = [[UINavigationBarAppearance alloc]init];
       appperance.backgroundColor = [UIColor whiteColor];
       self.navigationController.navigationBar.standardAppearance = appperance;
       self.navigationController.navigationBar.scrollEdgeAppearance = appperance;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *cacheUrlStr = [[NSUserDefaults standardUserDefaults]objectForKey:@"cacheUrlStr"];
        if(cacheUrlStr && cacheUrlStr.length){
            self.urlStr = cacheUrlStr;
        }else{
            [self showPlaceViewWithText:@"轻点【网址】开始，长按【网址】显示历史"];
        }
    });
    
    [self addReachabilityMonitoring];
}

- (void)initWebViewProgressView{
    UIView *progress = [[UIView alloc]initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.frame), 2)];
    progress.backgroundColor = [UIColor clearColor];
    [self.view addSubview:progress];

    CALayer *layer = [CALayer layer];
    layer.frame = CGRectMake(0, 0, 0, 2);
    layer.backgroundColor = [MainColor CGColor];
    [progress.layer addSublayer:layer];
    self.progressLayer = layer;
    
    // 确保webView已经初始化后再添加KVO
    if (self.webView) {
        [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    } else {
        NSLog(@"[警告] webView未初始化，无法添加KVO观察者");
    }
}

#pragma mark - Actions
#pragma mark 点击了重新加载网页
- (IBAction)webReloadAction:(id)sender {
    [self handleUrlLoad:self.currentUrlStr shouldCache:NO];
}

#pragma mark 点击了网页后退
- (IBAction)webBackAction:(id)sender {
    if (self.webView.canGoBack) {
        [self.webView goBack];
    } else {
        self.webBackBtn.enabled = NO;
    }
}

#pragma mark 点击了网页前进
- (IBAction)webNextAction:(id)sender {
    if (self.webView.canGoForward) {
        [self.webView goForward];
    } else {
        self.webNextBtn.enabled = NO;
    }
}

#pragma mark 点击了关于
- (IBAction)aboutAction:(id)sender {
    ZXIpaAboutVC *VC = [[ZXIpaAboutVC alloc]init];
    [self.navigationController pushViewController:VC animated:YES];
}

#pragma mark 点击了二维码
-(void)qrcodeItemAction{
    if(![UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]){
        [ALToastView showToastWithText:@"摄像头不可用"];
        return;
    }
    SGQRCodeScanningVC *VC = [[SGQRCodeScanningVC alloc] init];
    VC.resultBlock = ^(NSString *resultStr) {
        [self handelWithUrlStr:resultStr];
    };
    [self.navigationController pushViewController:VC animated:YES];
}
#pragma mark 点击了网址
-(void)inputAction{
    [self handleInputUrlFrom:InputUrlFromInput];
}

#pragma mark 长按了网址
-(void)inputLongPress:(UILongPressGestureRecognizer *)gesture{
    if(gesture.state != UIGestureRecognizerStateBegan){
        return;
    }
    ZXIpaUrlHisVC *VC = [[ZXIpaUrlHisVC alloc]init];
    VC.urlSelectedBlock = ^(NSString * _Nonnull urlStr) {
        self.urlStr = urlStr;
        self.urlStartHandled = YES;
    };
    [self.navigationController pushViewController:VC animated:YES];
}

#pragma mark 点击了底部网站标题
-(void)webTitleTap{
    [self handleInputUrlFrom:self.currentUrlStr && self.currentUrlStr.length ? InputUrlFromEdit : InputUrlFromInput];
}

#pragma mark 监听wkWebview加载进度
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        self.progressLayer.opacity = 1;
        if ([change[@"new"] floatValue] < [change[@"old"] floatValue]) {
            return;
        }
        self.progressLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width * [change[@"new"] floatValue], self.progressLayer.frame.size.height);
        if ([change[@"new"] floatValue] == 1) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.progressLayer.opacity = 0;
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.progressLayer.frame = CGRectMake(0, 0, 0, self.progressLayer.frame.size.height);
                self.title = MainTitle;
            });
        }
    }else{
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - WKNavigationDelegate
#pragma mark 网页将要开始加载
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    self.title = @"加载中...";
    if(!self.webTitleTf.text.length){
        self.webTitleTf.placeholder = @"loading...";
    }
    NSString *urlStr = navigationAction.request.URL.absoluteString;
    NSString *host = navigationAction.request.URL.host;
    if (!self.isDeveloperMode && [ZXAccessBlackHostList containsObject: host]) {
        [self showAlertWithTitle:@"访问禁止" message:@"很抱歉，因网站方的要求，IPA提取器已禁止您的操作！"];
        self.title = @"访问禁止";
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    if([urlStr matchesAnyRegexInArr:self.mobileprovisionRegulaArr]){
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:@"此网页想要安装一个描述文件以获取UDID，IPA提取器将尝试解析并跳转至描述文件安装后的回调地址，您也可以在Safari中继续操作。请选择您的操作以继续" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *analysisAction = [UIAlertAction actionWithTitle:@"解析此描述文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            [ZXIpaHttpRequest downLoadWithUrlStr:urlStr path:ZXMobileprovisionCachePath callBack:^(BOOL result, id  _Nonnull data) {
                if(result){
                    TCMobileProvision *mobileprovision = [[TCMobileProvision alloc] initWithData:
                        [NSData dataWithContentsOfFile:data]];
                    
                    if (mobileprovision && mobileprovision.dict && mobileprovision.dict[@"PayloadContent"] && [mobileprovision.dict[@"PayloadContent"] isKindOfClass:[NSDictionary class]] && mobileprovision.dict[@"PayloadContent"][@"URL"]) {
                        NSString *checkUrl = mobileprovision.dict[@"PayloadContent"][@"URL"];
                        ZXDeviceInfoModel *deviceInfoModel = [ZXDeviceInfo getDeviceInfo];
                        NSString *getUdidXMLTemplateStr = [[NSString alloc] initWithData:[[NSData alloc]initWithContentsOfFile:[[NSBundle mainBundle]pathForResource:@"GetUdidXMLTemplate" ofType:nil]] encoding:NSUTF8StringEncoding];
                        
                        getUdidXMLTemplateStr = [getUdidXMLTemplateStr replaceKeysWithValuesInDict:[deviceInfoModel zx_toDic]];
                        
                        NSData *xmlData = [getUdidXMLTemplateStr dataUsingEncoding:NSUTF8StringEncoding];
                        NSMutableURLRequest *xmlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:checkUrl]];
                        [xmlRequest setValue:@"application/pkcs7-signature" forHTTPHeaderField:@"Content-Type"];
                        [xmlRequest setValue:@"Profile/1.0" forHTTPHeaderField:@"User-Agent"];
                        [xmlRequest setValue:@"zh-CN,zh-Hans;q=0.9" forHTTPHeaderField:@"Accept-Language"];
                        [xmlRequest setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];
                        [xmlRequest setHTTPMethod:@"POST"];
                        [xmlRequest setHTTPBody:xmlData];
                        
                        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
                        config.HTTPShouldUsePipelining = NO;
                        config.HTTPShouldSetCookies = NO;
                        NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
                        NSURLSessionDataTask *task = [session dataTaskWithRequest:xmlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                    NSInteger statusCode = httpResponse.statusCode;
                                    NSDictionary *headers = httpResponse.allHeaderFields;
                                    NSString *location = [headers objectForKey:@"Location"];
                                    
                                    if (statusCode == 301 && location && location.length) {
                                        [ALToastView showToastWithText:@"成功解析描述文件安装后回调地址，跳转中..."];
                                        [self handleUrlLoad:location shouldCache:NO];
                                    }
                                }
                                [MBProgressHUD hideHUDForView:self.view animated:YES];
                            });
                        }];
                        [task resume];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [MBProgressHUD hideHUDForView:self.view animated:YES];
                            [self showAlertWithTitle:@"错误" message:@"mobileprovision文件解析失败"];
                        });
                    }
                }else{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [MBProgressHUD hideHUDForView:self.view animated:YES];
                        [self showAlertWithTitle:@"错误" message:[NSString stringWithFormat:@"mobileprovision文件下载失败，失败原因为:%@",((NSError *)data).localizedDescription]];
                    });
                }
            }];
        }];
        UIAlertAction *toSafariAction = [UIAlertAction actionWithTitle:@"在Safari中打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *url = [NSURL URLWithString:self.urlStr];
            if ([[UIApplication sharedApplication]canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url];
            } else {
                [ALToastView showToastWithText:@"跳转失败"];
            }
        }];
        
        [alertController addThemeAction:analysisAction];
        [alertController addThemeAction:toSafariAction];
        [alertController addThemeAction:cancelAction];
        [self presentViewController:alertController animated:YES completion:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if([[urlStr pathExtension] isEqualToString:@"ipa"] || [urlStr containsString:@".ipa&"]){
        if (!(self.self.ignoredIpaDownloadUrl && [self.ignoredIpaDownloadUrl isEqualToString:urlStr])){
            __block NSString *urlStrWithoutQuery = [urlStr regularWithPattern:@"^.*?\\.ipa"];
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前访问的地址可能是ipa文件下载地址，也可能是一个网页，请确认操作以继续！" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
            UIAlertAction *downloadAction = [UIAlertAction actionWithTitle:@"当作ipa文件下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                ZXIpaModel *ipaModel = [[ZXIpaModel alloc]init];
                if(!urlStrWithoutQuery || !urlStrWithoutQuery.length){
                    urlStrWithoutQuery = urlStr;
                }
                
                // 安全地设置title，避免解码失败导致nil
                NSString *decodedTitle = nil;
                @try {
                    decodedTitle = [[[urlStrWithoutQuery lastPathComponent] stringByDeletingPathExtension] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                } @catch (NSException *exception) {
                    NSLog(@"[解码] 解码URL失败: %@", exception.reason);
                    decodedTitle = nil;
                }
                
                if (!decodedTitle) {
                    // 如果解码失败，尝试直接使用未解码的路径
                    decodedTitle = [[urlStrWithoutQuery lastPathComponent] stringByDeletingPathExtension];
                    if (!decodedTitle || [decodedTitle length] == 0) {
                        decodedTitle = @"未知应用";
                    }
                }
                
                ipaModel.title = decodedTitle;
                ipaModel.downloadUrl = urlStr;
                ipaModel.sign = [ipaModel.downloadUrl md5Str];
                [self saveIpaModel:ipaModel];
                ZXLocalIpaVC *VC = [[ZXLocalIpaVC alloc]init];
                VC.ipaModel = ipaModel;
                [self.navigationController pushViewController:VC animated:YES];
            }];
            UIAlertAction *loadAction = [UIAlertAction actionWithTitle:@"当作网页访问" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                self.ignoredIpaDownloadUrl = urlStr;
                [self handleUrlLoad:urlStr shouldCache:NO];
            }];
            [alertController addThemeAction:cancelAction];
            [alertController addThemeAction:downloadAction];
            [alertController addThemeAction:loadAction];
            [self presentViewController:alertController animated:YES completion:nil];
            self.title = MainTitle;
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }else{
            self.ignoredIpaDownloadUrl = NULL;
        }
        
    }
    if([urlStr hasPrefix:@"itms-services://"] || [urlStr containsString:@"itemService="]){
        urlStr = [urlStr getPlistPathUrlStr];
        NSMutableURLRequest *newPlistReq;
        newPlistReq = [navigationAction.request mutableCopy];
        newPlistReq.URL = [NSURL URLWithString:urlStr];
        [ZXIpaHttpRequest downLoadWithUrlStr:urlStr path:ZXPlistCachePath callBack:^(BOOL result, id  _Nonnull data) {
            if(result){
                NSDictionary *plistDic = [[NSDictionary alloc]initWithContentsOfFile:data];
                ZXIpaModel *ipaModel = [[ZXIpaModel alloc]initWithDic:plistDic];
                [self saveIpaModel:ipaModel];
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:[NSString stringWithFormat:@"已成功提取\"%@\"的ipa信息，可在【历史】中查看！",ipaModel.title] preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"我知道了" style:UIAlertActionStyleCancel handler:nil];
                    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"查看详情" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        ZXIpaDetailVC *VC = [[ZXIpaDetailVC alloc]init];
                        VC.ipaModel = ipaModel;
                        [self.navigationController pushViewController:VC animated:YES];
                    }];
                    [alertController addThemeAction:cancelAction];
                    [alertController addThemeAction:confirmAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                    self.title = MainTitle;
                });
            }else{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showAlertWithTitle:@"错误" message:[NSString stringWithFormat:@"plist文件下载失败，失败原因为:%@",((NSError *)data).localizedDescription]];
                });
            }
        }];
        if(![urlStr containsString:@"itemService="]){
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark 网页已经开始加载
-(void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
    
}

#pragma mark 网页加载完成
-(void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
    self.title = MainTitle;
    self.webBackBtn.enabled = self.webView.canGoBack;
    self.webNextBtn.enabled = self.webView.canGoForward;
    
    [webView evaluateJavaScript:@"document.title" completionHandler:^(id _Nullable title, NSError * _Nullable error) {
        self.webTitleTf.text = title;
    }];
    
    [webView evaluateJavaScript:@"document.URL" completionHandler:^(id _Nullable urlStr, NSError * _Nullable error) {
        self.currentUrlStr = urlStr;
    }];
    
    self.webReloadBtn.enabled = YES;
    if(self.urlStartHandled){
        [webView evaluateJavaScript:@"location.protocol" completionHandler:^(id _Nullable protocol, NSError * _Nullable error) {
            [webView evaluateJavaScript:@"location.host" completionHandler:^(id _Nullable host, NSError * _Nullable error) {
                NSString *hostStr = [NSString stringWithFormat:@"%@//%@", protocol, host];
                [webView evaluateJavaScript:@"var getFavicon=function(){var favicon=undefined;var nodeList=document.getElementsByTagName('link');for(var i=0;i<nodeList.length;i++){if((nodeList[i].getAttribute('rel')=='icon')||(nodeList[i].getAttribute('rel')=='shortcut icon')){favicon=nodeList[i].getAttribute('href')}}return favicon};getFavicon();" completionHandler:^(id _Nullable favicon, NSError * _Nullable error) {
                    if(favicon && ![favicon hasPrefix:@"http"]){
                        favicon = [hostStr stringByAppendingString:favicon];
                    }
                    if(!favicon){
                        favicon = [NSString stringWithFormat:@"%@/favicon.ico", hostStr];
                    }
                    ZXIpaUrlHisModel *urlHisModel = [[ZXIpaUrlHisModel alloc]init];
                    urlHisModel.hostStr = hostStr;
                    urlHisModel.urlStr = self.currentUrlStr;
                    urlHisModel.title = self.webTitleTf.text;
                    urlHisModel.favicon = favicon;
                    NSArray *sameArr = [ZXIpaUrlHisModel zx_dbQuaryWhere:[NSString stringWithFormat:@"urlStr='%@'",urlHisModel.urlStr]];
                    if(sameArr.count){
                        [ZXIpaUrlHisModel zx_dbDropWhere:[NSString stringWithFormat:@"urlStr='%@'",urlHisModel.urlStr]];
                        NSString *oldUrlStr = ((ZXIpaUrlHisModel *)sameArr[0]).urlStr;
                        if(oldUrlStr && oldUrlStr.length){
                            urlHisModel.title = ((ZXIpaUrlHisModel *)sameArr[0]).title;
                        }
                    }
                    [urlHisModel zx_dbSave];
                }];
            }];
        }];
    }
    self.urlStartHandled = NO;
}

#pragma mark 网页加载失败
-(void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error{
    self.webBackBtn.enabled = self.webView.canGoBack;
    self.webNextBtn.enabled = self.webView.canGoForward;
    
    NSString *errInfo = error.localizedDescription;
    if(!errInfo)return;
    if(![errInfo isEqualToString:@"Frame load interrupted"]){
        self.title = @"加载失败";
        [ALToastView showToastWithText:errInfo];
    }
}

#pragma mark - UITextFieldDelegate
-(BOOL)textFieldShouldBeginEditing:(UITextField *)textField{
    return NO;
}

#pragma mark - NSURLSessionDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // 禁用所有重定向
}

#pragma mark - private
#pragma mark 处理url
-(void)handelWithUrlStr:(NSString *)urlStr{
    self.urlStr = urlStr;
    self.urlStartHandled = YES;
}

#pragma mark 处理从剪贴板中获取url并跳转
-(void)pasteboardStrLoadUrl:(NSNotification *)nf{
    NSString *urlStr = nf.object;
    self.urlStartHandled = YES;
    self.urlStr = urlStr;
    [self.navigationController popToRootViewControllerAnimated:YES];
}

#pragma mark 保存ipaModel
-(void)saveIpaModel:(ZXIpaModel *)ipaModel{
    // 确保title不为nil
    if (!ipaModel.title || [ipaModel.title length] == 0) {
        NSLog(@"[保存] 警告: IPA标题为空，设置为默认标题");
        ipaModel.title = @"未知应用";
    }
    
    NSArray *sameArr = [ZXIpaModel zx_dbQuaryWhere:[NSString stringWithFormat:@"sign='%@'",ipaModel.sign]];
    ipaModel.localPath = [sameArr.firstObject valueForKey:@"localPath"];
    if(sameArr.count){
        [ZXIpaModel zx_dbDropWhere:[NSString stringWithFormat:@"sign='%@'",ipaModel.sign]];
    }
    ipaModel.fromPageUrl = [[NSUserDefaults standardUserDefaults]objectForKey:@"cacheUrlStr"];
    NSDate *date = [NSDate date];
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    ipaModel.time = [format stringFromDate:date];
    [ipaModel zx_dbSave];
}

- (void)updateMobileprovisionRegulaArr {
    self.mobileprovisionRegulaArr = [ZXDataStoreCache readObjForKey:ZXMobileprovisionRegularCacheKey];
    if (self.mobileprovisionRegulaArr == nil) {
        [ZXIpaHttpRequest getUrl:ZXMobileprovisionUrlRegularGetPath callBack:^(BOOL result, id  _Nonnull data) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            if (result) {
                NSDictionary *resultDic = [data zx_toDic];
                NSArray *mobileprovisionRegulaArr = resultDic[@"matches"];
                self.mobileprovisionRegulaArr = mobileprovisionRegulaArr;
            } else {
                self.mobileprovisionRegulaArr = ZXMobileprovisionRegularDefault;
            }
            [ZXDataStoreCache saveObj:self.mobileprovisionRegulaArr forKey:ZXMobileprovisionRegularCacheKey];
        }];
        
    }
}

- (void)updateDeveloperMode {
    self.isDeveloperMode = [[NSUserDefaults standardUserDefaults]objectForKey:@"developerMode"] != nil;
    NSString *cacheUrlStr = [[NSUserDefaults standardUserDefaults]objectForKey:@"cacheUrlStr"];
    if (cacheUrlStr) {
        self.currentUrlStr = cacheUrlStr;
        [self handleUrlLoad:self.currentUrlStr shouldCache:NO];
    }
}

- (void)handleUrlLoad:(NSString *)urlStr shouldCache:(BOOL)shouldCache{
    if(![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"] && ![urlStr hasPrefix:@"itms-services://"]){
        urlStr = [@"http://" stringByAppendingString:urlStr];
    }
    _urlStr = urlStr;
    
    // 使用更安全的URL编码方式
    NSString *encodedUrlStr = nil;
    @try {
        // 先尝试使用现代API
        encodedUrlStr = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    } @catch (NSException *exception) {
        NSLog(@"[警告] 现代URL编码失败: %@", exception.reason);
        // 如果失败，回退到旧API
        encodedUrlStr = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
            kCFAllocatorDefault,
            (CFStringRef)urlStr,
            (CFStringRef)@"!$&'()*+,-./:;=?@_~%#[]",
            NULL,
            kCFStringEncodingUTF8
        ));
    }
    
    NSURL *url = [NSURL URLWithString:encodedUrlStr];
    if(!url){
        self.title = @"URL无效";
        NSLog(@"[错误] 无法创建URL: %@", urlStr);
        return;
    }
    
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    if(shouldCache){
        [[NSUserDefaults standardUserDefaults]setObject:urlStr forKey:@"cacheUrlStr"];
        [[NSUserDefaults standardUserDefaults]synchronize];
    }
    [self removePlaceView];
    self.title = @"加载中...";
}

#pragma mark 处理url输入事件
-(void)handleInputUrlFrom:(InputUrlFrom)from{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:from == InputUrlFromInput ? @"输入下载页URL" : @"编辑下载页URL" message:@"等待网页加载完毕点击下载即可自动拦截ipa下载链接" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *inputTf = alertController.textFields[0];
        [inputTf becomeFirstResponder];
        NSString *urlStr = inputTf.text;
        if(!urlStr.length){
            self.title = @"URL不得为空";
            return;
        }
        if(from == InputUrlFromInput){
            [self handelWithUrlStr:urlStr];
        }else{
            [self handleUrlLoad:urlStr shouldCache:NO];
        }
    }];
    [alertController addThemeAction:cancelAction];
    [alertController addThemeAction:confirmAction];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"请输入URL";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        if(from == InputUrlFromInput){
            NSString *cacheUrlStr = [[NSUserDefaults standardUserDefaults]objectForKey:@"cacheUrlStr"];
            if(cacheUrlStr){
                textField.text = cacheUrlStr;
            }
        }else{
            textField.text = self.currentUrlStr;
        }
    }];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)addReachabilityMonitoring{
    __weak typeof(self) weakSelf = self;
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (status != AFNetworkReachabilityStatusNotReachable) {
            [strongSelf updateMobileprovisionRegulaArr];
        } else {
            [strongSelf showAlertWithTitle:@"提示" message:@"网络错误，请检查网络设置"];
        }
    }];
    
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
}

#pragma mark setter

- (void)setUrlStr:(NSString *)urlStr{
    [self handleUrlLoad:urlStr shouldCache:YES];
}
@end
