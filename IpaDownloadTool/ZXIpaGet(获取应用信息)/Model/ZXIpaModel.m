//
//  ZXIpaModel.m
//  IpaDownloadTool
//
//  Created by 李兆祥 on 2019/4/28.
//  Copyright © 2019 李兆祥. All rights reserved.
//

#import "ZXIpaModel.h"
#import "NSString+ZXMD5.h"
@implementation ZXIpaModel{
    BOOL hasLoadLocalPath;
}

-(instancetype)initWithDic:(NSDictionary *)dic{
    if(self = [super init]){
        NSDictionary *itemsDic = dic[@"items"][0];
        NSDictionary *metadataDic = itemsDic[@"metadata"];
        NSDictionary *assetsDic = itemsDic[@"assets"][0];
        
        // 确保title不为nil
        NSString *title = metadataDic[@"title"];
        if (!title || [title length] == 0) {
            title = @"未知应用";
        }
        self.title = title;
        
        self.bundleId = metadataDic[@"bundle-identifier"];
        self.version = metadataDic[@"bundle-version"];
        self.iconUrl = metadataDic[@"icon-url"];
        self.downloadUrl = assetsDic[@"url"];
        self.sign = [self.downloadUrl md5Str];
        
        NSDate *date = [NSDate date];
        NSDateFormatter *format = [[NSDateFormatter alloc] init];
        [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        self.time = [format stringFromDate:date];
        
        NSString *fileName = [NSString stringWithFormat:@"%@.ipa",self.title];
        self.localPath = [ZXIpaDownloadedPath stringByAppendingPathComponent:fileName];
    }
    return self;
}

-(NSString *)title{
    if(_title && _title.length > 50){
        _title = [_title substringToIndex:50];
    }
    return _title;
}

-(NSString *)localPath{
    if(!hasLoadLocalPath){
        NSString *localPath = [NSString stringWithFormat:@"%@/%@/%@/%@.ipa",ZXDocPath,ZXIpaDownloadedPath,self.sign,self.title];
        NSString *oldLocalPath = [NSString stringWithFormat:@"%@/%@/%@.ipa",ZXDocPath,ZXIpaDownloadedPath,self.sign];
        if([ZXFileManage isExistWithPath:oldLocalPath]){
            _localPath = oldLocalPath;
        }else {
            _localPath = localPath;
        }
        hasLoadLocalPath = YES;
    }
    return _localPath;
}
@end
