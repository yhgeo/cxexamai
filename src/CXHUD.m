#import "CXHUD.h"
#import "CXCommon.h"
#import "CXAI.h"

#pragma mark - 窗口

@interface CXHUDWindow : UIWindow
@end

@implementation CXHUDWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma mark - 设置页

@interface CXSettingsViewController : UIViewController
@end

@implementation CXSettingsViewController {
    UITextField *_base, *_model, *_key;
    UISwitch *_auto, *_guard, *_hud;
    UISlider *_delay;
    UILabel *_delayLabel;
    UILabel *_testLabel;
    UILabel *_pathLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [NSString stringWithFormat:@"CXExamAI %@", CX_VERSION];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(save)];

    CXConfig *c = [CXConfig shared];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-40],
    ]];

    _base = [self field:@"接口地址，如 https://api.deepseek.com" value:c.baseURL];
    _model = [self field:@"模型，如 deepseek-chat" value:c.model];
    _key = [self field:@"API Key" value:c.apiKey];
    _key.secureTextEntry = YES;

    _auto = [UISwitch new];
    _auto.on = c.autoAnswer;
    _guard = [UISwitch new];
    _guard.on = c.guardEnabled;
    _hud = [UISwitch new];
    _hud.on = c.hudEnabled;

    _delayLabel = [UILabel new];
    _delayLabel.font = [UIFont systemFontOfSize:14];
    _delayLabel.text = [NSString stringWithFormat:@"开始作答延迟：%.1f 秒", c.startDelay];
    _delay = [UISlider new];
    _delay.minimumValue = 0;
    _delay.maximumValue = 5;
    _delay.value = c.startDelay;
    [_delay addTarget:self action:@selector(delayChanged) forControlEvents:UIControlEventValueChanged];

    UIButton *test = [self button:@"测试接口连通" action:@selector(testAPI)];
    UIButton *share = [self button:@"导出日志（分享到微信/QQ）" action:@selector(shareLog)];

    _testLabel = [UILabel new];
    _testLabel.font = [UIFont systemFontOfSize:13];
    _testLabel.textColor = [UIColor secondaryLabelColor];
    _testLabel.numberOfLines = 0;

    _pathLabel = [UILabel new];
    _pathLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _pathLabel.textColor = [UIColor secondaryLabelColor];
    _pathLabel.numberOfLines = 0;
    _pathLabel.text = [NSString stringWithFormat:@"日志完整路径（可长按复制）：\n%@", [CXLog path]];

    UILabel *tip = [UILabel new];
    tip.font = [UIFont systemFontOfSize:12];
    tip.textColor = [UIColor secondaryLabelColor];
    tip.numberOfLines = 0;
    tip.text = @"单击悬浮球展开答案，双击立即重答，长按打开本页。\n抓不到题时会把页面存成 cx-dom-*.html，同目录下。";

    NSArray *views = @[_base, _model, _key,
                       [self rowWithTitle:@"自动答题" control:_auto],
                       [self rowWithTitle:@"考试页防检测" control:_guard],
                       [self rowWithTitle:@"显示悬浮球" control:_hud],
                       _delayLabel, _delay, test, _testLabel,
                       [self rowWithTitle:@"日志" control:[UIView new]],
                       _pathLabel, share, tip];
    for (UIView *v in views) [stack addArrangedSubview:v];
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [b.heightAnchor constraintEqualToConstant:36].active = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UITextField *)field:(NSString *)placeholder value:(NSString *)value {
    UITextField *t = [[UITextField alloc] init];
    t.placeholder = placeholder;
    t.text = value;
    t.borderStyle = UITextBorderStyleRoundedRect;
    t.font = [UIFont systemFontOfSize:14];
    t.autocapitalizationType = UITextAutocapitalizationTypeNone;
    t.autocorrectionType = UITextAutocorrectionTypeNo;
    t.clearButtonMode = UITextFieldViewModeWhileEditing;
    [t.heightAnchor constraintEqualToConstant:38].active = YES;
    return t;
}

- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:14];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    return row;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[CXHUD shared] setVisible:[CXConfig shared].hudEnabled];
}

- (void)delayChanged {
    _delayLabel.text = [NSString stringWithFormat:@"开始作答延迟：%.1f 秒", _delay.value];
}

- (void)save {
    CXConfig *c = [CXConfig shared];
    c.baseURL = _base.text.length ? _base.text : @"https://api.deepseek.com";
    c.model = _model.text.length ? _model.text : @"deepseek-chat";
    c.apiKey = _key.text ?: @"";
    c.autoAnswer = _auto.isOn;
    c.guardEnabled = _guard.isOn;
    c.hudEnabled = _hud.isOn;
    c.startDelay = _delay.value;
    [c save];
    CXLOG(@"设置已保存 base=%@ model=%@ keyLen=%lu", c.baseURL, c.model, (unsigned long)c.apiKey.length);
    [[CXHUD shared] setVisible:c.hudEnabled];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)testAPI {
    _testLabel.text = @"测试中…";
    __weak typeof(self) weakSelf = self;
    [[CXAI shared] testConnection:^(BOOL ok, NSString *msg) {
        CXSettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_testLabel.text = [NSString stringWithFormat:@"%@ %@", ok ? @"成功" : @"失败", msg ?: @""];
    }];
}

- (void)shareLog {
    NSString *path = [CXLog path];
    NSMutableArray *items = [NSMutableArray array];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [items addObject:[NSURL fileURLWithPath:path]];
    }
    NSString *text = [NSString stringWithFormat:@"CXExamAI %@\n%@\n（日志文件不存在时说明插件未产生任何输出）", CX_VERSION, path];
    [items addObject:text];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    if (vc.popoverPresentationController) {
        vc.popoverPresentationController.sourceView = self.view;
        vc.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    }
    [self presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - HUD

@implementation CXHUD {
    CXHUDWindow *_window;
    UIView *_ball;
    UILabel *_ballLabel;
    UIView *_panel;
    UILabel *_qLabel;
    UITextView *_aView;
    UILabel *_hintLabel;
    BOOL _panelShown;
    NSInteger _hideSeq;
}

+ (instancetype)shared {
    static CXHUD *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [CXHUD new]; });
    return s;
}

- (void)install {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_window) return;
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
        if (!scene) return;

        self->_window = [[CXHUDWindow alloc] initWithWindowScene:scene];
        self->_window.windowLevel = UIWindowLevelAlert + 5;
        self->_window.backgroundColor = [UIColor clearColor];
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = [UIColor clearColor];
        self->_window.rootViewController = root;
        self->_window.hidden = NO;

        [self buildBallInView:root.view];
        [self buildPanelInView:root.view];
        self->_window.hidden = ![CXConfig shared].hudEnabled;
        CXLOG(@"HUD 已安装 v%@ bounds=%@", CX_VERSION, NSStringFromCGRect(self->_window.bounds));
    });
}

- (void)buildBallInView:(UIView *)host {
    CGFloat w = host.bounds.size.width;
    if (w < 100) w = [UIScreen mainScreen].bounds.size.width;
    _ball = [[UIView alloc] initWithFrame:CGRectMake(w - 58, 150, 46, 46)];
    _ball.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.35];
    _ball.layer.cornerRadius = 23;
    _ball.layer.borderWidth = 0.5;
    _ball.layer.borderColor = [UIColor whiteColor].CGColor;
    _ball.alpha = 0.75;

    _ballLabel = [[UILabel alloc] initWithFrame:_ball.bounds];
    _ballLabel.text = @"AI";
    _ballLabel.textColor = [UIColor whiteColor];
    _ballLabel.font = [UIFont boldSystemFontOfSize:13];
    _ballLabel.textAlignment = NSTextAlignmentCenter;
    [_ball addSubview:_ballLabel];
    [host addSubview:_ball];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
    dbl.numberOfTapsRequired = 2;
    [tap requireGestureRecognizerToFail:dbl];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.8;

    [_ball addGestureRecognizer:pan];
    [_ball addGestureRecognizer:tap];
    [_ball addGestureRecognizer:dbl];
    [_ball addGestureRecognizer:press];
}

- (void)buildPanelInView:(UIView *)host {
    _panel = [UIView new];
    _panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.96];
    _panel.layer.cornerRadius = 14;
    _panel.layer.borderWidth = 0.5;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    _panel.hidden = YES;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:_panel];

    _qLabel = [UILabel new];
    _qLabel.textColor = [UIColor whiteColor];
    _qLabel.font = [UIFont systemFontOfSize:13];
    _qLabel.numberOfLines = 3;
    _qLabel.text = @"等待抓题…";

    _aView = [UITextView new];
    _aView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _aView.layer.cornerRadius = 8;
    _aView.editable = NO;
    _aView.selectable = YES;
    _aView.textColor = [UIColor whiteColor];
    _aView.font = [UIFont systemFontOfSize:15];
    _aView.text = @"";
    [_aView.heightAnchor constraintEqualToConstant:132].active = YES;

    _hintLabel = [UILabel new];
    _hintLabel.textColor = [UIColor lightGrayColor];
    _hintLabel.font = [UIFont systemFontOfSize:11];
    _hintLabel.numberOfLines = 1;
    _hintLabel.text = @"单击收起 · 双击重答 · 长按设置";

    UIButton *again = [UIButton buttonWithType:UIButtonTypeSystem];
    [again setTitle:@"重新作答" forState:UIControlStateNormal];
    [again addTarget:self action:@selector(triggerManual) forControlEvents:UIControlEventTouchUpInside];

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    [settings setTitle:@"设置" forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"收起" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[again, settings, close]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    [row.heightAnchor constraintEqualToConstant:34].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_qLabel, _aView, _hintLabel, row]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [_panel.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [_panel.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-12],
    ]];
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:_ball.superview];
    CGPoint c = _ball.center;
    _ball.center = CGPointMake(c.x + p.x, c.y + p.y);
    [g setTranslation:CGPointZero inView:_ball.superview];
}

- (void)handleTap {
    _panelShown = !_panelShown;
    _panel.hidden = !_panelShown;
}

- (void)handleDoubleTap {
    [self triggerManual];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self openSettings];
}

- (void)triggerManual {
    if (self.onManualTrigger) self.onManualTrigger();
    _panel.hidden = NO;
    _panelShown = YES;
    _qLabel.text = @"正在重新抓题…";
    _aView.text = @"";
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_window.hidden = YES;
        CXSettingsViewController *vc = [CXSettingsViewController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        UIViewController *top = CXTopViewController();
        if (top) [top presentViewController:nav animated:YES completion:nil];
    });
}

- (void)setStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_ballLabel) return;
        self->_ballLabel.text = status.length > 4 ? [status substringToIndex:4] : status;
        self->_hintLabel.text = status;
    });
}

- (void)showAnswer:(NSDictionary *)ans question:(NSString *)stem {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *letters = ans[@"answer"] ?: @[];
        NSString *text = ans[@"text"] ?: @"";
        NSMutableString *s = [NSMutableString string];
        if (letters.count) [s appendFormat:@"选项：%@\n", [letters componentsJoinedByString:@""]];
        if (text.length) [s appendString:text];
        if (s.length == 0) [s appendString:@"（空答案）"];
        self->_qLabel.text = stem.length ? stem : @"（未取到题干）";
        self->_aView.text = s;
        self->_hintLabel.text = @"双击重答 · 长按设置";
        if ([UIScreen mainScreen].isCaptured) return;   // 录屏中不弹面板
        self->_panel.hidden = NO;
        self->_panelShown = YES;
    });
}

- (void)setVisible:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_window.hidden = !visible;
    });
}

- (void)hideNow {
    if ([NSThread isMainThread]) {
        _hideSeq++;
        _window.hidden = YES;
        NSInteger seq = _hideSeq;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (seq != self->_hideSeq) return;
            self->_window.hidden = ![CXConfig shared].hudEnabled;
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideNow]; });
    }
}

- (void)hideTemporarily:(NSTimeInterval)seconds {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_hideSeq++;
        NSInteger seq = self->_hideSeq;
        self->_window.hidden = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (seq != self->_hideSeq) return;
            self->_window.hidden = ![CXConfig shared].hudEnabled;
        });
    });
}

@end
