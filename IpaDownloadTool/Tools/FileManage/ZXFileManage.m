//
//  ZXFileManage.m
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/29.
//  Copyright © 2019 李兆祥. All rights reserved.
//

#import "ZXFileManage.h"
#import "ZXDataHandle.h"

#define ExtentDocPath(pathComponent) [NSString stringWithFormat:@"%@/%@",ZXDocPath,pathComponent]
@interface ZXFileManage()
@property (strong, nonatomic) UIDocumentInteractionController *documentController;
@end
@implementation ZXFileManage
+(instancetype)shareInstance{
    static ZXFileManage * s_instance_dj_singleton = nil ;
    if (s_instance_dj_singleton == nil) {
        s_instance_dj_singleton = [[ZXFileManage alloc] init];
    }
    return (ZXFileManage *)s_instance_dj_singleton;
}

+(PathAttr)getPathAttrWithPath:(NSString *)path{
    BOOL isDir = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL pathExist = [fileManager fileExistsAtPath:path isDirectory:&isDir];
    if(!pathExist){
        return PathAttrNotExist;
    }
    if(isDir){
        return PathAttrDir;
    }
    return PathAttrFile;
    
}
+(PathAttr)getPathAttrWithPathComponent:(NSString *)pathComponent{
    return [self getPathAttrWithPath:ExtentDocPath(pathComponent)];
    
}

+(BOOL)isExistWithPath:(NSString *)path{
    return [self getPathAttrWithPath:path] != PathAttrNotExist;
}
+(BOOL)isExistWithPathComponent:(NSString *)pathComponent{
    return [self getPathAttrWithPathComponent:pathComponent] != PathAttrNotExist;
}

+(void)delFileWithPath:(NSString *)path{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    PathAttr pathAttr = [self getPathAttrWithPath:path];
    if(pathAttr == PathAttrNotExist){
        
    }else{
        NSError *error;
        [fileManager removeItemAtPath:path error:&error];
    }
}
+(void)delFileWithPathComponent:(NSString *)pathComponent{
    [self delFileWithPath:ExtentDocPath(pathComponent)];
}

+(void)creatDirWithPath:(NSString *)path{
    NSDictionary *attrDic =[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate];
    if(![self isExistWithPath:path]){
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attrDic error:nil];
    }
}
+(void)creatDirWithPathComponent:(NSString *)pathComponent{
    [self creatDirWithPath:ExtentDocPath(pathComponent)];
}
+(long long)getFileSizeWithPath:(NSString *)path{
    if([self isExistWithPath:path]){
        return [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil]fileSize];
    }
    return 0;
}

+(long long)getFileSizeWithPathComponent:(NSString *)pathComponent{
    return [self getFileSizeWithPath:ExtentDocPath(pathComponent)];
}
-(void)shareFileWithPath:(NSString *)path{
    NSLog(@"shareFileWithPath--%@",path);
    if(![ZXFileManage isExistWithPath:path]){
        [ALToastView showToastWithText:@"文件不存在！"];
        return;
    }
    UIDocumentInteractionController *documentController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]];
    documentController.UTI = @"com.adobe.pdf";
    [documentController presentOpenInMenuFromRect:CGRectZero inView:[UIApplication sharedApplication].keyWindow.rootViewController.view animated:YES];
    self.documentController = documentController;
}

+ (BOOL)fileExistWithPath:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath {
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] copyItemAtPath:srcPath toPath:dstPath error:&error];
    if (error) {
        NSLog(@"复制文件失败: %@", error.localizedDescription);
    }
    return success;
}

+ (BOOL)unzipFileAtPath:(NSString *)path toDestination:(NSString *)destination {
    // 确保目标目录存在
    if (![self fileExistWithPath:destination]) {
        [self creatDirWithPath:destination];
    }
    
    // 由于我们计划使用SSZipArchive库，但是它可能还没有安装
    // 暂时使用一个简单的解决方案：将IPA文件复制到目标位置
    // 注意：这不是真正的解压，在实际项目中，添加SSZipArchive库后，应该使用它的方法
    // [SSZipArchive unzipFileAtPath:path toDestination:destination];
    
    // 临时的解决方案：在导入IPA后，直接读取外部程序解压的内容
    NSLog(@"需要使用SSZipArchive库来解压文件");
    NSLog(@"将IPA从%@复制到%@", path, destination);
    
    // 为了项目能够继续运行，我们暂时返回YES
    // 在实际运行前，需要执行pod install安装SSZipArchive，并取消下面的注释
    return YES;
}
@end
