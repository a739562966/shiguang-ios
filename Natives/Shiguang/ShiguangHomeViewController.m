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
    [ShiguangBootstrap start];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
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
    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:6]];

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

    [self.contentStack addArrangedSubview:[self makeSpacerWithHeight:16]];
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
