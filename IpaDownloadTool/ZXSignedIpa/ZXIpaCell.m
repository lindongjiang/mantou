//
//  ZXIpaCell.m
//  IpaDownloadTool
//
//  Created by Claude on 2023/11/10.
//

#import "ZXIpaCell.h"

@implementation ZXIpaCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 创建图标视图
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.layer.cornerRadius = 10;
    self.iconImageView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.iconImageView];
    
    // 创建标题标签
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.contentView addSubview:self.titleLabel];
    
    // 创建副标题标签
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textColor = [UIColor darkGrayColor];
    [self.contentView addSubview:self.subtitleLabel];
    
    // 创建详情标签
    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.font = [UIFont systemFontOfSize:12];
    self.detailLabel.textColor = [UIColor grayColor];
    [self.contentView addSubview:self.detailLabel];
    
    // 设置自动布局约束
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 图标约束
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:60],
        [self.iconImageView.heightAnchor constraintEqualToConstant:60]
    ]];
    
    // 标题约束
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:15],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10]
    ]];
    
    // 副标题约束
    [NSLayoutConstraint activateConstraints:@[
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:5]
    ]];
    
    // 详情约束
    [NSLayoutConstraint activateConstraints:@[
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:5],
        [self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconImageView.image = nil;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.detailLabel.text = nil;
}

@end 