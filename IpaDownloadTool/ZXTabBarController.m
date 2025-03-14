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
    // 主页 - 获取应用信息
    ZXIpaGetVC *ipaGetVC = [[ZXIpaGetVC alloc] init];
    UINavigationController *ipaGetNav = [[UINavigationController alloc] initWithRootViewController:ipaGetVC];
    
    // 导入IPA - 新增的页面
    ZXIpaImportVC *ipaImportVC = [[ZXIpaImportVC alloc] init];
    UINavigationController *ipaImportNav = [[UINavigationController alloc] initWithRootViewController:ipaImportVC];
    
    // 下载列表 - 已下载应用
    ZXLocalIpaVC *localIpaVC = [[ZXLocalIpaVC alloc] init];
    UINavigationController *localIpaNav = [[UINavigationController alloc] initWithRootViewController:localIpaVC];
    
    // 历史记录
    ZXIpaHisVC *hisVC = [[ZXIpaHisVC alloc] init];
    UINavigationController *hisNav = [[UINavigationController alloc] initWithRootViewController:hisVC];
    
    // 关于
    ZXIpaAboutVC *aboutVC = [[ZXIpaAboutVC alloc] init];
    UINavigationController *aboutNav = [[UINavigationController alloc] initWithRootViewController:aboutVC];
    
    // 使用系统图标（iOS 13以上可用）
    if (@available(iOS 13.0, *)) {
        ipaGetNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"主页" image:[UIImage systemImageNamed:@"house"] tag:0];
        ipaImportNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"导入" image:[UIImage systemImageNamed:@"square.and.arrow.down"] tag:1];
        localIpaNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"已下载" image:[UIImage systemImageNamed:@"arrow.down.circle"] tag:2];
        hisNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"历史" image:[UIImage systemImageNamed:@"clock"] tag:3];
        aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"关于" image:[UIImage systemImageNamed:@"info.circle"] tag:4];
    } else {
        // iOS 13以下使用标题
        ipaGetNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"主页" image:nil tag:0];
        ipaImportNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"导入" image:nil tag:1];
        localIpaNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"已下载" image:nil tag:2];
        hisNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"历史" image:nil tag:3];
        aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"关于" image:nil tag:4];
    }
    
    // 设置TabBar的视图控制器
    self.viewControllers = @[ipaGetNav, ipaImportNav, localIpaNav, hisNav, aboutNav];
}

@end 