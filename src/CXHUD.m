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

#pragma mark - 安全容器（截图/录屏穿透）

@interface CXSecureContainer : UIView
@property (nonatomic, strong) UIView *content;
@end

@implementation CXSecureContainer {
    UITextField *_secureField;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _secureField = [[UITextField alloc] initWithFrame:self.bounds];
        _secureField.secureTextEntry = YES;
        _secureField.backgroundColor = [UIColor clearColor];
        _secureField.textColor = [UIColor clearColor];
        _secureField.tintColor = [UIColor clearColor];
        _secureField.userInteractionEnabled = NO;
        _secureField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_secureField];

        _content = [[UIView alloc] initWithFrame:self.bounds];
        _content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_secureField addSubview:_content];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _secureField.frame = self.bounds;
    UIView *canvas = _secureField.subviews.firstObject;
    if (canvas && _content.superview != canvas) {
        [_content removeFromSuperview];
        [canvas addSubview:_content];
    }
    UIView *host = _content.superview ?: self;
    _content.frame = host.bounds;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    CGPoint p = [self convertPoint:point toView:_content];
    if ([_content pointInside:p withEvent:event]) {
        return [_content hitTest:p withEvent:event];
    }
    return nil;
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
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"CXExamAI";
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

    UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
    [test setTitle:@"测试接口连通" forState:UIControlStateNormal];
    [test addTarget:self action:@selector(testAPI) forControlEvents:UIControlEventTouchUpInside];

    _testLabel = [UILabel new];
    _testLabel.font = [UIFont systemFontOfSize:13];
    _testLabel.textColor = [UIColor secondaryLabelColor];
    _testLabel.numberOfLines = 0;

    UILabel *tip = [UILabel new];
    tip.font = [UIFont systemFontOfSize:12];
    tip.textColor = [UIColor secondaryLabelColor];
    tip.numberOfLines = 0;
    tip.text = @"日志：学习通沙盒 Documents/CXExamAI.log\n单击悬浮球展开答案，双击立即作答，长按打开设置。";

    NSArray *views = @[_base, _model, _key,
                       [self rowWithTitle:@"自动答题" control:_auto],
                       [self rowWithTitle:@"考试页防检测" control:_guard],
                       [self rowWithTitle:@"显示悬浮球" control:_hud],
                       _delayLabel, _delay, test, _testLabel, tip];
    for (UIView *v in views) [stack addArrangedSubview:v];
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
    [[CXHUD shared] setVisible:c.hudEnabled];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)testAPI {
    _testLabel.text = @"测试中…";
    __weak typeof(self) weakSelf = self;
    [[CXAI shared] testConnection:^(BOOL ok, NSString *msg) {
        weakSelf->_testLabel.text = [NSString stringWithFormat:@"%@ %@", ok ? @"成功" : @"失败", msg ?: @""];
    }];
}

@end

#pragma mark - HUD

@implementation CXHUD {
    CXHUDWindow *_window;
    UIView *_ball;
    UILabel *_ballLabel;
    CXSecureContainer *_panel;
    UILabel *_qLabel;
    UITextView *_aView;
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

        self->_window = scene ? [[CXHUDWindow alloc] initWithWindowScene:scene]
                              : [[CXHUDWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self->_window.windowLevel = UIWindowLevelAlert + 5;
        self->_window.backgroundColor = [UIColor clearColor];
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = [UIColor clearColor];
        self->_window.rootViewController = root;
        self->_window.hidden = NO;

        [self buildBallInView:root.view];
        [self buildPanelInView:root.view];
        self->_window.hidden = ![CXConfig shared].hudEnabled;
        CXLOG(@"HUD 已安装 %@", NSStringFromCGRect(self->_window.bounds));
    });
}

- (void)buildBallInView:(UIView *)host {
    CGRect screen = [UIScreen mainScreen].bounds;
    _ball = [[UIView alloc] initWithFrame:CGRectMake(screen.size.width - 58, 150, 46, 46)];
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
    CGRect screen = [UIScreen mainScreen].bounds;
    _panel = [[CXSecureContainer alloc] initWithFrame:CGRectMake(16, screen.size.height - 300, screen.size.width - 32, 236)];
    _panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
    _panel.layer.cornerRadius = 12;
    _panel.hidden = YES;
    [host addSubview:_panel];

    UIView *c = _panel.content;
    _qLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, CGRectGetWidth(_panel.bounds) - 24, 54)];
    _qLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _qLabel.textColor = [UIColor whiteColor];
    _qLabel.font = [UIFont systemFontOfSize:13];
    _qLabel.numberOfLines = 3;
    [c addSubview:_qLabel];

    _aView = [[UITextView alloc] initWithFrame:CGRectMake(12, 68, CGRectGetWidth(_panel.bounds) - 24, 110)];
    _aView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _aView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _aView.layer.cornerRadius = 8;
    _aView.editable = NO;
    _aView.selectable = YES;
    _aView.textColor = [UIColor whiteColor];
    _aView.font = [UIFont systemFontOfSize:15];
    [c addSubview:_aView];

    UIButton *again = [UIButton buttonWithType:UIButtonTypeSystem];
    again.frame = CGRectMake(12, 186, 90, 36);
    again.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [again setTitle:@"重新作答" forState:UIControlStateNormal];
    [again addTarget:self action:@selector(triggerManual) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:again];

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    settings.frame = CGRectMake(CGRectGetWidth(_panel.bounds) - 102, 186, 90, 36);
    settings.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [settings setTitle:@"设置" forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:settings];
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
    _qLabel.text = @"手动触发了抓题…";
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
        self->_qLabel.text = stem;
        self->_aView.text = s;
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
