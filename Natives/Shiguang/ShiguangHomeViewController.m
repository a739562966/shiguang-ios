#import "ShiguangHomeViewController.h"
#import "ShiguangAuthenticator.h"
#import "ShiguangBootstrap.h"
#import "ShiguangConfig.h"

#import "../LauncherPreferences.h"
#import "../LauncherPreferencesViewController.h"
#import "../authenticator/BaseAuthenticator.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>

#include <unistd.h>

static UIColor *ShiguangColorGreen(void) {
    return [UIColor colorWithRed:0.18 green:0.62 blue:0.27 alpha:1.0];
}

static UIColor *ShiguangColorSecondary(void) {
    return [UIColor colorWithWhite:1 alpha:0.55];
}

static NSString *ShiguangFormatSpeed(int64_t bytesPerSecond) {
    if (bytesPerSecond <= 0) {
        return @"";
    }
    if (bytesPerSecond >= 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f MB/s", (double)bytesPerSecond / 1024.0 / 1024.0];
    }
    if (bytesPerSecond >= 1024) {
        return [NSString stringWithFormat:@"%.0f KB/s", (double)bytesPerSecond / 1024.0];
    }
    return [NSString stringWithFormat:@"%lld B/s", (long long)bytesPerSecond];
}

static BOOL ShiguangIsTrollStore(void) {
    NSString *marker = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"../_TrollStore"];
    return [NSFileManager.defaultManager fileExistsAtPath:marker];
}

static NSString *ShiguangFormatAnnouncementDate(NSNumber *timestamp) {
    if (timestamp == nil || timestamp.doubleValue <= 0) {
        return @"";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue / 1000.0];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:date];
}

static NSComparisonResult ShiguangCompareVersion(NSString *lhs, NSString *rhs) {
    NSArray<NSString *> *a = [lhs componentsSeparatedByString:@"."];
    NSArray<NSString *> *b = [rhs componentsSeparatedByString:@"."];
    NSUInteger count = MAX(a.count, b.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSInteger left = i < a.count ? a[i].integerValue : 0;
        NSInteger right = i < b.count ? b[i].integerValue : 0;
        if (left > right) {
            return NSOrderedDescending;
        }
        if (left < right) {
            return NSOrderedAscending;
        }
    }
    return NSOrderedSame;
}

@interface ShiguangHomeViewController () <UITextFieldDelegate>

@property(nonatomic) CAGradientLayer *gradientLayer;
@property(nonatomic) UIScrollView *scrollView;
@property(nonatomic) UIStackView *contentStack;

@property(nonatomic) UIStackView *loginStack;
@property(nonatomic) UITextField *usernameField;
@property(nonatomic) UITextField *passwordField;
@property(nonatomic) UIButton *loginButton;
@property(nonatomic) UIButton *registerButton;

@property(nonatomic) UIStackView *accountStack;
@property(nonatomic) UILabel *accountNameLabel;
@property(nonatomic) UIButton *logoutButton;

@property(nonatomic) UIButton *startButton;
@property(nonatomic) UIProgressView *progressView;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UILabel *messageLabel;

@property(nonatomic) UIView *announcementCard;
@property(nonatomic) UILabel *announcementDateLabel;
@property(nonatomic) UILabel *announcementLabel;
@property(nonatomic) UIButton *passwordButton;
@property(nonatomic) UIButton *musicButton;
@property(nonatomic) UIButton *versionButton;
@property(nonatomic) AVAudioPlayer *musicPlayer;
@property(nonatomic) BOOL checkingUpdate;

@property(nonatomic) BOOL busy;

@end

@implementation ShiguangHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupBackground];
    [self setupViews];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(bootstrapDidUpdate:)
                                               name:ShiguangBootstrapDidUpdateNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(keyboardWillChangeFrame:)
                                               name:UIKeyboardWillChangeFrameNotification
                                             object:nil];

    [self refreshAccountState];
    [self refreshUI];
    [self loadAnnouncement];
    [ShiguangBootstrap start];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.musicPlayer stop];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshAccountState];
    [self refreshUI];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.gradientLayer.frame = self.view.bounds;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UI

- (void)setupBackground {
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.055 blue:0.10 alpha:1.0];
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.06 green:0.10 blue:0.18 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.025 green:0.04 blue:0.075 alpha:1.0].CGColor
    ];
    self.gradientLayer.startPoint = CGPointMake(0, 0);
    self.gradientLayer.endPoint = CGPointMake(0.2, 1);
    [self.view.layer insertSublayer:self.gradientLayer atIndex:0];
}

- (UITextField *)makeTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    field.textColor = UIColor.whiteColor;
    field.tintColor = ShiguangColorGreen();
    field.font = [UIFont systemFontOfSize:16];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:placeholder
            attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.42]}];
    field.layer.cornerRadius = 10;
    field.layer.borderWidth = 1;
    field.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    field.delegate = self;

    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 48)];
    field.leftView = padding;
    field.leftViewMode = UITextFieldViewModeAlways;

    [field.heightAnchor constraintEqualToConstant:48].active = YES;
    return field;
}

- (UIButton *)makeFilledButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.35] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    button.backgroundColor = ShiguangColorGreen();
    button.layer.cornerRadius = 10;
    [button.heightAnchor constraintEqualToConstant:46].active = YES;
    return button;
}

- (UIButton *)makeOutlinedButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:ShiguangColorGreen() forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.35] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.clearColor;
    button.layer.cornerRadius = 10;
    button.layer.borderWidth = 1;
    button.layer.borderColor = ShiguangColorGreen().CGColor;
    [button.heightAnchor constraintEqualToConstant:46].active = YES;
    return button;
}

- (void)setupViews {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 14;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:20],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:20],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-20],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-40]
    ]];

    // 顶部：logo + 标题 + 设置
    UIImageView *logoView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo"]];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 12;
    logoView.clipsToBounds = YES;
    [logoView.widthAnchor constraintEqualToConstant:52].active = YES;
    [logoView.heightAnchor constraintEqualToConstant:52].active = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = SHIGUANG_APP_NAME;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    titleLabel.numberOfLines = 1;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.65;

    UIView *headerSpacer = [[UIView alloc] init];
    [headerSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    settingsButton.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    [settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventPrimaryActionTriggered];
    [settingsButton.widthAnchor constraintEqualToConstant:44].active = YES;
    [settingsButton.heightAnchor constraintEqualToConstant:44].active = YES;

    UIStackView *headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[logoView, titleLabel, headerSpacer, settingsButton]];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.spacing = 12;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = [NSString stringWithFormat:@"Minecraft %@ · Fabric", SHIGUANG_MC_VERSION];
    subtitleLabel.textColor = ShiguangColorSecondary();
    subtitleLabel.font = [UIFont systemFontOfSize:13];

    [self.contentStack addArrangedSubview:headerStack];
    [self.contentStack addArrangedSubview:subtitleLabel];
    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:2]];
    [self.contentStack addArrangedSubview:[self makeAnnouncementCard]];
    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:4]];

    // 登录 / 注册
    self.usernameField = [self makeTextFieldWithPlaceholder:@"用户名"];
    self.passwordField = [self makeTextFieldWithPlaceholder:@"密码"];
    self.passwordField.secureTextEntry = YES;
    self.passwordField.returnKeyType = UIReturnKeyGo;

    self.loginButton = [self makeFilledButtonWithTitle:@"登录"];
    [self.loginButton addTarget:self action:@selector(actionLogin) forControlEvents:UIControlEventPrimaryActionTriggered];
    self.registerButton = [self makeOutlinedButtonWithTitle:@"注册"];
    [self.registerButton addTarget:self action:@selector(actionRegister) forControlEvents:UIControlEventPrimaryActionTriggered];

    UIStackView *loginButtonRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.loginButton, self.registerButton]];
    loginButtonRow.axis = UILayoutConstraintAxisHorizontal;
    loginButtonRow.spacing = 10;
    loginButtonRow.distribution = UIStackViewDistributionFillEqually;

    self.loginStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.usernameField, self.passwordField, loginButtonRow]];
    self.loginStack.axis = UILayoutConstraintAxisVertical;
    self.loginStack.spacing = 10;

    // 已登录账号
    UIImageView *accountIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    accountIcon.translatesAutoresizingMaskIntoConstraints = NO;
    accountIcon.tintColor = ShiguangColorGreen();
    accountIcon.contentMode = UIViewContentModeScaleAspectFit;
    [accountIcon.widthAnchor constraintEqualToConstant:44].active = YES;
    [accountIcon.heightAnchor constraintEqualToConstant:44].active = YES;

    self.accountNameLabel = [[UILabel alloc] init];
    self.accountNameLabel.textColor = UIColor.whiteColor;
    self.accountNameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

    UILabel *accountHintLabel = [[UILabel alloc] init];
    accountHintLabel.text = @"已登录";
    accountHintLabel.textColor = ShiguangColorSecondary();
    accountHintLabel.font = [UIFont systemFontOfSize:12];

    UIStackView *accountLabels = [[UIStackView alloc] initWithArrangedSubviews:@[self.accountNameLabel, accountHintLabel]];
    accountLabels.axis = UILayoutConstraintAxisVertical;
    accountLabels.spacing = 2;

    UIView *accountSpacer = [[UIView alloc] init];
    [accountSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.logoutButton setTitle:@"退出" forState:UIControlStateNormal];
    [self.logoutButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.7] forState:UIControlStateNormal];
    self.logoutButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.logoutButton addTarget:self action:@selector(actionLogout) forControlEvents:UIControlEventPrimaryActionTriggered];

    self.accountStack = [[UIStackView alloc] initWithArrangedSubviews:@[accountIcon, accountLabels, accountSpacer, self.logoutButton]];
    self.accountStack.axis = UILayoutConstraintAxisHorizontal;
    self.accountStack.alignment = UIStackViewAlignmentCenter;
    self.accountStack.spacing = 10;
    self.accountStack.hidden = YES;

    [self.contentStack addArrangedSubview:self.loginStack];
    [self.contentStack addArrangedSubview:self.accountStack];
    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:10]];

    // 开始游戏
    self.startButton = [self makeFilledButtonWithTitle:@"登录后开始游戏"];
    self.startButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.startButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.startButton.titleLabel.minimumScaleFactor = 0.6;
    [self.startButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [self.startButton addTarget:self action:@selector(actionStartGame) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self.contentStack addArrangedSubview:self.startButton];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor = ShiguangColorGreen();
    self.progressView.trackTintColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.progressView.hidden = YES;
    [self.progressView.heightAnchor constraintEqualToConstant:4].active = YES;
    [self.contentStack addArrangedSubview:self.progressView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textColor = ShiguangColorSecondary();
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.statusLabel];

    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.textColor = [UIColor systemRedColor];
    self.messageLabel.font = [UIFont systemFontOfSize:13];
    self.messageLabel.numberOfLines = 0;
    [self.contentStack addArrangedSubview:self.messageLabel];

    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:12]];

    // 与桌面版一致：意见反馈 / QQ 群 / 音乐 / 修改密码
    UIButton *feedbackButton = [self makeCompactButtonWithTitle:@"意见反馈" action:@selector(actionFeedback)];
    UIButton *qqButton = [self makeCompactButtonWithTitle:@"QQ 群" action:@selector(actionOpenQQ)];
    self.musicButton = [self makeCompactButtonWithTitle:@"音乐" action:@selector(actionToggleMusic)];
    self.passwordButton = [self makeCompactButtonWithTitle:@"修改密码" action:@selector(actionChangePassword)];
    self.passwordButton.enabled = NO;

    UIStackView *moreStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        feedbackButton, qqButton, self.musicButton, self.passwordButton
    ]];
    moreStack.axis = UILayoutConstraintAxisHorizontal;
    moreStack.spacing = 8;
    moreStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:moreStack];

    self.versionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.versionButton setTitle:[NSString stringWithFormat:@"版本 %@ · 检查更新", SHIGUANG_VERSION]
                        forState:UIControlStateNormal];
    [self.versionButton setTitleColor:ShiguangColorSecondary() forState:UIControlStateNormal];
    self.versionButton.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.versionButton addTarget:self action:@selector(actionCheckUpdate) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self.contentStack addArrangedSubview:self.versionButton];

    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:6]];
}

- (UIButton *)makeCompactButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.82] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.3] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    button.layer.cornerRadius = 9;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    [button.heightAnchor constraintEqualToConstant:38].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (UIView *)makeAnnouncementCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
    card.layer.cornerRadius = 12;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    card.hidden = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"更新公告";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];

    UIView *titleSpacer = [[UIView alloc] init];
    [titleSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.announcementDateLabel = [[UILabel alloc] init];
    self.announcementDateLabel.textColor = ShiguangColorSecondary();
    self.announcementDateLabel.font = [UIFont systemFontOfSize:11];
    self.announcementDateLabel.textAlignment = NSTextAlignmentRight;

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, titleSpacer, self.announcementDateLabel
    ]];
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.spacing = 8;

    self.announcementLabel = [[UILabel alloc] init];
    self.announcementLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    self.announcementLabel.font = [UIFont systemFontOfSize:13];
    self.announcementLabel.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, self.announcementLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
    ]];

    self.announcementCard = card;
    return card;
}

- (UIView *)makeSpacerWithHeight:(CGFloat)height {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    return view;
}

#pragma mark - 状态刷新

- (void)refreshAccountState {
    if (BaseAuthenticator.current == nil) {
        return;
    }
    // 由 BaseAuthenticator 自行加载上次选中的拾光账号
}

- (void)refreshUI {
    BOOL loggedIn = [ShiguangAuthenticator isCurrentShiguang];
    NSString *username = BaseAuthenticator.current.authData[@"username"];

    self.loginStack.hidden = loggedIn;
    self.accountStack.hidden = !loggedIn;
    self.accountNameLabel.text = username ?: @"";
    self.passwordButton.enabled = loggedIn;

    ShiguangBootstrap *bootstrap = ShiguangBootstrap.shared;

    if (bootstrap.running) {
        NSString *text = bootstrap.message ?: @"正在准备运行环境…";
        NSString *speed = ShiguangFormatSpeed(bootstrap.speed);
        if (speed.length > 0) {
            text = [text stringByAppendingFormat:@" · %@", speed];
        }
        [self.startButton setTitle:text forState:UIControlStateNormal];
        self.startButton.enabled = NO;
    } else if (!loggedIn) {
        [self.startButton setTitle:@"登录后开始游戏" forState:UIControlStateNormal];
        self.startButton.enabled = NO;
    } else if (bootstrap.ready) {
        [self.startButton setTitle:@"开始游戏" forState:UIControlStateNormal];
        self.startButton.enabled = YES;
    } else {
        [self.startButton setTitle:@"点击下载游戏" forState:UIControlStateNormal];
        self.startButton.enabled = YES;
    }

    self.progressView.hidden = !bootstrap.running || bootstrap.progress < 0;
    if (!self.progressView.hidden) {
        self.progressView.progress = (float)bootstrap.progress;
    }

    if (bootstrap.running) {
        NSString *speed = ShiguangFormatSpeed(bootstrap.speed);
        self.statusLabel.text = speed.length > 0
            ? [NSString stringWithFormat:@"%@ · %@", bootstrap.message ?: @"", speed]
            : (bootstrap.message ?: @"");
    } else if (bootstrap.errorMessage.length > 0) {
        self.statusLabel.text = bootstrap.errorMessage;
    } else {
        self.statusLabel.text = bootstrap.message ?: @"";
    }
}

#pragma mark - 公告 / 反馈 / 音乐 / 密码 / 版本

- (void)loadAnnouncement {
    NSURL *url = [NSURL URLWithString:SHIGUANG_ANNOUNCEMENT_URL];
    if (url == nil) {
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10;
    [request setValue:SHIGUANG_USER_AGENT forHTTPHeaderField:@"User-Agent"];

    __weak ShiguangHomeViewController *weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *item = nil;
        if (data.length > 0) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSDictionary.class]) {
                id list = json[@"list"];
                if (![list isKindOfClass:NSArray.class]) {
                    id nested = json[@"data"];
                    if ([nested isKindOfClass:NSDictionary.class]) {
                        list = nested[@"list"];
                    }
                }
                if ([list isKindOfClass:NSArray.class] && [list count] > 0) {
                    id first = list[0];
                    if ([first isKindOfClass:NSDictionary.class]) {
                        item = first;
                    }
                }
            }
        }

        NSString *content = [item[@"content"] isKindOfClass:NSString.class] ? item[@"content"] : nil;
        NSNumber *createdAt = [item[@"createdAt"] isKindOfClass:NSNumber.class] ? item[@"createdAt"] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            ShiguangHomeViewController *strongSelf = weakSelf;
            if (strongSelf == nil || content.length == 0) {
                return;
            }
            strongSelf.announcementLabel.text = content;
            strongSelf.announcementDateLabel.text = ShiguangFormatAnnouncementDate(createdAt);
            strongSelf.announcementCard.hidden = NO;
        });
    }] resume];
}

- (void)openExternalURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)actionFeedback {
    [self openExternalURL:SHIGUANG_FEEDBACK_URL];
}

- (void)actionOpenQQ {
    [self openExternalURL:SHIGUANG_QQ_URL];
}

- (void)actionToggleMusic {
    if (self.musicPlayer.isPlaying) {
        [self.musicPlayer stop];
        [self.musicButton setTitle:@"音乐" forState:UIControlStateNormal];
        return;
    }

    NSString *path = [NSBundle.mainBundle pathForResource:@"music" ofType:@"mp3"];
    if (path.length == 0) {
        self.messageLabel.textColor = [UIColor systemRedColor];
        self.messageLabel.text = @"未找到音乐文件";
        return;
    }

    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryAmbient error:nil];
    [session setActive:YES error:nil];

    NSError *error = nil;
    self.musicPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (self.musicPlayer == nil || error != nil) {
        self.messageLabel.textColor = [UIColor systemRedColor];
        self.messageLabel.text = @"音乐播放失败";
        return;
    }
    self.musicPlayer.numberOfLoops = -1;
    [self.musicPlayer play];
    [self.musicButton setTitle:@"音乐 开" forState:UIControlStateNormal];
}

- (void)actionChangePassword {
    if (![ShiguangAuthenticator isCurrentShiguang]) {
        self.messageLabel.textColor = [UIColor systemRedColor];
        self.messageLabel.text = @"请先登录";
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改密码"
        message:@"修改成功后其他设备需要重新登录" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"旧密码";
        field.secureTextEntry = YES;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"新密码（至少 6 位）";
        field.secureTextEntry = YES;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"确认新密码";
        field.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    __weak ShiguangHomeViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
        NSString *oldPassword = alert.textFields[0].text ?: @"";
        NSString *newPassword = alert.textFields[1].text ?: @"";
        NSString *confirm = alert.textFields[2].text ?: @"";
        ShiguangHomeViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (newPassword.length < 6) {
            strongSelf.messageLabel.textColor = [UIColor systemRedColor];
            strongSelf.messageLabel.text = @"新密码至少 6 位";
            return;
        }
        if (![newPassword isEqualToString:confirm]) {
            strongSelf.messageLabel.textColor = [UIColor systemRedColor];
            strongSelf.messageLabel.text = @"两次输入的新密码不一致";
            return;
        }

        strongSelf.messageLabel.textColor = ShiguangColorSecondary();
        strongSelf.messageLabel.text = @"正在修改密码…";
        [ShiguangAuthenticator changePassword:oldPassword to:newPassword callback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ShiguangHomeViewController *innerSelf = weakSelf;
                if (innerSelf == nil) {
                    return;
                }
                innerSelf.messageLabel.textColor = success ? ShiguangColorSecondary() : [UIColor systemRedColor];
                innerSelf.messageLabel.text = success
                    ? @"密码修改成功"
                    : ([status isKindOfClass:NSString.class] ? status : @"密码修改失败");
            });
        }];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)actionCheckUpdate {
    if (self.checkingUpdate) {
        return;
    }
    self.checkingUpdate = YES;
    [self.versionButton setTitle:@"正在检查更新…" forState:UIControlStateNormal];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:SHIGUANG_LATEST_RELEASE_URL]];
    request.timeoutInterval = 10;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

    __weak ShiguangHomeViewController *weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *tag = [json isKindOfClass:NSDictionary.class] ? json[@"tag_name"] : nil;
        NSString *pageURL = [json isKindOfClass:NSDictionary.class] ? json[@"html_url"] : nil;
        if (![tag isKindOfClass:NSString.class]) {
            tag = nil;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            ShiguangHomeViewController *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.checkingUpdate = NO;
            [strongSelf.versionButton setTitle:[NSString stringWithFormat:@"版本 %@ · 检查更新", SHIGUANG_VERSION]
                                     forState:UIControlStateNormal];

            if (error != nil || tag.length == 0) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"检查更新失败"
                    message:@"无法连接更新服务器，可手动前往下载页查看。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"前往下载页" style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                    [strongSelf openExternalURL:SHIGUANG_RELEASES_URL];
                }]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
                return;
            }

            NSString *latest = [tag hasPrefix:@"v"] || [tag hasPrefix:@"V"] ? [tag substringFromIndex:1] : tag;
            if (ShiguangCompareVersion(latest, SHIGUANG_VERSION) == NSOrderedDescending) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:
                    [NSString stringWithFormat:@"发现新版本 %@", latest]
                    message:[NSString stringWithFormat:@"当前版本 %@，是否前往下载？", SHIGUANG_VERSION]
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"前往下载" style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                    [strongSelf openExternalURL:pageURL.length > 0 ? pageURL : SHIGUANG_RELEASES_URL];
                }]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已是最新版本"
                    message:[NSString stringWithFormat:@"当前版本 %@", SHIGUANG_VERSION]
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
            }
        });
    }] resume];
}

#pragma mark - 登录

- (void)actionLogin {
    [self loginOrRegister:NO];
}

- (void)actionRegister {
    [self loginOrRegister:YES];
}

- (void)loginOrRegister:(BOOL)registerAccount {
    if (self.busy) {
        return;
    }
    NSString *username = [self.usernameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *password = self.passwordField.text;
    if (username.length < 3 || password.length == 0) {
        self.messageLabel.text = @"请输入用户名和密码（用户名至少 3 位）";
        return;
    }

    self.busy = YES;
    self.messageLabel.text = nil;
    [self setControlsEnabled:NO];
    [self.loginButton setTitle:@"请稍候…" forState:UIControlStateNormal];

    __weak ShiguangHomeViewController *weakSelf = self;
    Callback callback = ^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ShiguangHomeViewController *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.busy = NO;
            [strongSelf setControlsEnabled:YES];
            [strongSelf.loginButton setTitle:@"登录" forState:UIControlStateNormal];

            if (success) {
                strongSelf.messageLabel.textColor = ShiguangColorSecondary();
                strongSelf.messageLabel.text = registerAccount ? @"注册成功，已登录" : @"登录成功";
                setPrefObject(@"internal.selected_account", BaseAuthenticator.current.authData[@"username"] ?: @"");
                strongSelf.usernameField.text = nil;
                strongSelf.passwordField.text = nil;
                [strongSelf.view endEditing:YES];
                [strongSelf refreshUI];
                [ShiguangBootstrap start];
            } else {
                strongSelf.messageLabel.textColor = [UIColor systemRedColor];
                strongSelf.messageLabel.text = [status isKindOfClass:NSString.class]
                    ? status : @"登录失败，请稍后重试";
            }
        });
    };

    if (registerAccount) {
        [ShiguangAuthenticator registerWithUsername:username password:password callback:callback];
    } else {
        [ShiguangAuthenticator loginWithUsername:username password:password callback:callback];
    }
}

- (void)actionLogout {
    BaseAuthenticator.current = nil;
    setPrefObject(@"internal.selected_account", @"");
    self.messageLabel.text = nil;
    [self refreshUI];
}

- (void)setControlsEnabled:(BOOL)enabled {
    self.usernameField.enabled = enabled;
    self.passwordField.enabled = enabled;
    self.loginButton.enabled = enabled;
    self.registerButton.enabled = enabled;
}

#pragma mark - 启动游戏

- (void)actionStartGame {
    if (self.busy) {
        return;
    }
    if (![ShiguangAuthenticator isCurrentShiguang]) {
        self.messageLabel.text = @"请先登录";
        return;
    }

    ShiguangBootstrap *bootstrap = ShiguangBootstrap.shared;
    if (bootstrap.running) {
        return;
    }
    if (!bootstrap.ready) {
        [ShiguangBootstrap retry];
        self.messageLabel.text = nil;
        return;
    }

    self.startButton.enabled = NO;
    self.statusLabel.text = @"正在校验登录状态…";

    __weak ShiguangHomeViewController *weakSelf = self;
    [self ensureJITWithHandler:^{
        [ShiguangAuthenticator ensureValidWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ShiguangHomeViewController *strongSelf = weakSelf;
                if (strongSelf == nil) {
                    return;
                }
                if (!success) {
                    strongSelf.startButton.enabled = YES;
                    strongSelf.messageLabel.text = [status isKindOfClass:NSString.class]
                        ? status : @"登录状态已失效，请重新登录";
                    [strongSelf refreshUI];
                    return;
                }
                setPrefObject(@"internal.selected_account", BaseAuthenticator.current.authData[@"username"] ?: @"");
                [strongSelf launchMinecraft];
            });
        }];
    }];
}

- (void)launchMinecraft {
    NSDictionary *metadata = ShiguangBootstrap.shared.metadata;
    if (metadata == nil) {
        self.messageLabel.text = @"游戏尚未准备完成";
        self.startButton.enabled = YES;
        [ShiguangBootstrap retry];
        return;
    }
    self.statusLabel.text = @"正在启动游戏…";
    UIKit_launchMinecraftSurfaceVC(self.view.window, metadata);
}

- (void)ensureJITWithHandler:(void (^)(void))handler {
    if (isJITEnabled(false) || getPrefBool(@"debug.debug_skip_wait_jit")) {
        handler();
        return;
    }

    if (ShiguangIsTrollStore()) {
        self.statusLabel.text = @"正在启用 JIT…";
        NSString *scheme = [NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@",
            NSBundle.mainBundle.bundleIdentifier];
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:scheme] options:@{} completionHandler:nil];

        __weak ShiguangHomeViewController *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            for (NSInteger i = 0; i < 300; i++) {
                if (isJITEnabled(false)) {
                    break;
                }
                usleep(200 * 1000);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isJITEnabled(false)) {
                    handler();
                    return;
                }
                ShiguangHomeViewController *strongSelf = weakSelf;
                strongSelf.startButton.enabled = YES;
                strongSelf.messageLabel.text = @"JIT 未能启用，请在 TrollStore 中为启动器开启 JIT 后重试";
                [strongSelf refreshUI];
            });
        });
        return;
    }

    self.startButton.enabled = YES;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要开启 JIT"
        message:@"iOS 需要 JIT 才能运行 Minecraft。推荐使用 TrollStore 安装；若使用 AltStore/SideStore，请连接电脑启用 JIT 后再启动游戏。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 设置

- (void)openSettings {
    LauncherPreferencesViewController *controller = [[LauncherPreferencesViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成"
        style:UIBarButtonItemStyleDone
        target:self
        action:@selector(dismissSettings)];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)dismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 通知与键盘

- (void)bootstrapDidUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshUI];
    });
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
        return YES;
    }
    [textField resignFirstResponder];
    [self actionLogin];
    return YES;
}

@end
