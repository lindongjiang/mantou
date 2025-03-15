//
//  ZXTabBarController.m
//  IpaDownloadTool
//
//  Created on 2023/3/15.
//  Copyright © 2023. All rights reserved.
//

#import "ZXTabBarController.h"
#import "ZXIpaGetVC.h"
#import "ZXLocalIpaVC.h"
#import "ZXIpaHisVC.h"
#import "ZXIpaAboutVC.h"
#import "ZXIpaImportVC.h"
#import "ZXCertificateManageVC.h"
#import "ZXIpaDownloadVC.h"
#import "ZXSignedIpaVC.h"

@implementation ZXTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupViewControllers];
    
    // 设置TabBar的外观
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        self.tabBar.standardAppearance = appearance;
        
        if (@available(iOS 15.0, *)) {
            self.tabBar.scrollEdgeAppearance = appearance;
        }
    }
    
    // 设置TabBar的颜色
    self.tabBar.tintColor = MainColor;
    
    // 添加剪贴板URL加载通知的观察者
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePasteboardUrlNotification:) name:ZXPasteboardStrLoadUrlNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 处理剪贴板URL加载通知
- (void)handlePasteboardUrlNotification:(NSNotification *)notification {
    // 切换到主页标签
    self.selectedIndex = 0;
}

- (void)setupViewControllers {
    // IPA下载页面 - 整合了IPA提取器、下载中/已下载和IPA提取历史
    ZXIpaDownloadVC *ipaDownloadVC = [[ZXIpaDownloadVC alloc] init];
    UINavigationController *ipaDownloadNav = [[UINavigationController alloc] initWithRootViewController:ipaDownloadVC];
    
    // 导入IPA - 新增的页面
    ZXIpaImportVC *ipaImportVC = [[ZXIpaImportVC alloc] init];
    UINavigationController *ipaImportNav = [[UINavigationController alloc] initWithRootViewController:ipaImportVC];
    
    // 已签名IPA - 新增的页面
    ZXSignedIpaVC *signedIpaVC = [[ZXSignedIpaVC alloc] init];
    UINavigationController *signedIpaNav = [[UINavigationController alloc] initWithRootViewController:signedIpaVC];
    
    // 证书管理 - 新增页面
    ZXCertificateManageVC *certificateVC = [[ZXCertificateManageVC alloc] init];
    UINavigationController *certificateNav = [[UINavigationController alloc] initWithRootViewController:certificateVC];
    
    // 关于
    ZXIpaAboutVC *aboutVC = [[ZXIpaAboutVC alloc] init];
    UINavigationController *aboutNav = [[UINavigationController alloc] initWithRootViewController:aboutVC];
    
    // 使用系统图标（iOS 13以上可用）
    if (@available(iOS 13.0, *)) {
        ipaDownloadNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"IPA下载" image:[UIImage systemImageNamed:@"arrow.down.app"] tag:0];
        ipaImportNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"导入" image:[UIImage systemImageNamed:@"square.and.arrow.down"] tag:1];
        signedIpaNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"已签名" image:[UIImage systemImageNamed:@"checkmark.seal"] tag:2];
        certificateNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"证书" image:[UIImage systemImageNamed:@"shield"] tag:3];
        aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"关于" image:[UIImage systemImageNamed:@"info.circle"] tag:4];
    } else {
        // iOS 13以下使用标题
        ipaDownloadNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"IPA下载" image:nil tag:0];
        ipaImportNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"导入" image:nil tag:1];
        signedIpaNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"已签名" image:nil tag:2];
        certificateNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"证书" image:nil tag:3];
        aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"关于" image:nil tag:4];
    }
    
    // 设置TabBar的视图控制器
    self.viewControllers = @[ipaDownloadNav, ipaImportNav, signedIpaNav, certificateNav, aboutNav];
}

@end 
