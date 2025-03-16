//
//  ZXIpaCell.h
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXIpaCell : UITableViewCell

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *detailLabel;

@end

NS_ASSUME_NONNULL_END 