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
    UITextView *_logView;
    UILabel *_sizeLabel;
    UISwitch *_vision;
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

    _auto = [UISwitch new]; _auto.on = c.autoAnswer;
    _guard = [UISwitch new]; _guard.on = c.guardEnabled;
    _hud = [UISwitch new]; _hud.on = c.hudEnabled;
    _vision = [UISwitch new]; _vision.on = c.visionEnabled;

    _delayLabel = [UILabel new];
    _delayLabel.font = [UIFont systemFontOfSize:14];
    _delayLabel.text = [NSString stringWithFormat:@"开始作答延迟：%.1f 秒", c.startDelay];
    _delay = [UISlider new];
    _delay.minimumValue = 0; _delay.maximumValue = 5; _delay.value = c.startDelay;
    [_delay addTarget:self action:@selector(delayChanged) forControlEvents:UIControlEventValueChanged];

    UIButton *test = [self button:@"测试接口连通" action:@selector(testAPI)];

    _testLabel = [UILabel new];
    _testLabel.font = [UIFont systemFontOfSize:13];
    _testLabel.textColor = [UIColor secondaryLabelColor];
    _testLabel.numberOfLines = 0;

    _logView = [UITextView new];
    _logView.editable = NO;
    _logView.selectable = YES;
    _logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _logView.layer.cornerRadius = 10;
    _logView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logView.textColor = [UIColor labelColor];
    _logView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [_logView.heightAnchor constraintEqualToConstant:220].active = YES;
    _logView.text = [CXLog tail:60];

    UIButton *refresh = [self button:@"刷新日志" action:@selector(refreshLog)];
    UIButton *share = [self button:@"导出日志 + DOM 快照" action:@selector(shareLog)];
    UIButton *clean = [self button:@"清理日志与 DOM" action:@selector(cleanupFiles)];
    UIButton *resetPanel = [self button:@"重置悬浮窗位置" action:@selector(resetPanelPos)];

    _sizeLabel = [UILabel new];
    _sizeLabel.font = [UIFont systemFontOfSize:12];
    _sizeLabel.textColor = [UIColor secondaryLabelColor];
    _sizeLabel.numberOfLines = 1;
    _sizeLabel.text = @"";

    UILabel *logTitle = [UILabel new];
    logTitle.text = @"最近日志（60 行）";
    logTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    logTitle.textColor = [UIColor secondaryLabelColor];

    UILabel *pathLabel = [UILabel new];
    pathLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    pathLabel.textColor = [UIColor secondaryLabelColor];
    pathLabel.numberOfLines = 2;
    pathLabel.text = [CXLog path];

    UILabel *tip = [UILabel new];
    tip.font = [UIFont systemFontOfSize:12];
    tip.textColor = [UIColor secondaryLabelColor];
    tip.numberOfLines = 0;
    tip.text = @"单击悬浮球展开答案，双击立即重答，长按打开本页。\n面板可按住拖动，位置会自动记住。\n模型名填你的接口实际支持的名称，接口换模型后同步改这里。";

    NSArray *views = @[_base, _model, _key,
                       [self rowWithTitle:@"自动答题" control:_auto],
                       [self rowWithTitle:@"考试页防检测" control:_guard],
                       [self rowWithTitle:@"显示悬浮球" control:_hud],
                       [self rowWithTitle:@"识别题目图片（需视觉模型）" control:_vision],
                       _delayLabel, _delay, test, _testLabel,
                       logTitle, _sizeLabel, _logView, refresh, clean, share, resetPanel, pathLabel, tip];
    for (UIView *v in views) [stack addArrangedSubview:v];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLog];
}

- (void)refreshLog {
    _logView.text = [CXLog tail:60];
    [_logView setContentOffset:CGPointZero animated:NO];
    unsigned long long sz = [CXLog logSize];
    NSInteger domCount = 0;
    unsigned long long domSize = 0;
    NSString *dir = [[CXLog path] stringByDeletingLastPathComponent];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        if ([f hasPrefix:@"cx-dom-"] && [f hasSuffix:@".html"]) {
            domCount++;
            NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
            domSize += a ? [a fileSize] : 0;
        }
    }
    _sizeLabel.text = [NSString stringWithFormat:@"日志 %.1f KB · DOM %ld 个 %.1f MB（自动保留最近 3 个）",
                       sz / 1024.0, (long)domCount, domSize / 1048576.0];
}

- (void)cleanupFiles {
    [CXLog cleanupAll];
    [self refreshLog];
}

- (void)resetPanelPos {
    [[CXHUD shared] resetPanelPosition];
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
    c.visionEnabled = _vision.isOn;
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
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *items = [NSMutableArray array];
    if ([fm fileExistsAtPath:path]) [items addObject:[NSURL fileURLWithPath:path]];

    NSMutableArray *doms = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([f hasPrefix:@"cx-dom-"] && [f hasSuffix:@".html"]) [doms addObject:f];
    }
    [doms sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [b compare:a]; }];
    for (NSUInteger i = 0; i < MIN(doms.count, (NSUInteger)2); i++) {
        [items addObject:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:doms[i]]]];
    }
    if (items.count == 0) [items addObject:[NSString stringWithFormat:@"CXExamAI %@ 暂无日志", CX_VERSION]];
    [items addObject:[NSString stringWithFormat:@"CXExamAI %@\n%@", CX_VERSION, path]];

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
    UIVisualEffectView *_panel;
    UILabel *_qLabel;
    UILabel *_bigLabel;
    UILabel *_aTextLabel;
    UILabel *_hintLabel;
    UIView *_answerBox;
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
    _ball = [[UIView alloc] initWithFrame:CGRectMake(w - 52, 150, 40, 40)];
    _ball.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.55];
    _ball.layer.cornerRadius = 20;
    _ball.layer.borderWidth = 0.5;
    _ball.layer.borderColor = [UIColor whiteColor].CGColor;

    _ballLabel = [[UILabel alloc] initWithFrame:_ball.bounds];
    _ballLabel.text = @"AI";
    _ballLabel.textColor = [UIColor whiteColor];
    _ballLabel.font = [UIFont boldSystemFontOfSize:12];
    _ballLabel.textAlignment = NSTextAlignmentCenter;
    [_ball addSubview:_ballLabel];
    [host addSubview:_ball];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap)];
    dbl.numberOfTapsRequired = 2;
    [tap requireGestureRecognizerToFail:dbl];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.7;

    [_ball addGestureRecognizer:pan];
    [_ball addGestureRecognizer:tap];
    [_ball addGestureRecognizer:dbl];
    [_ball addGestureRecognizer:press];
}

- (void)buildPanelInView:(UIView *)host {
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _panel = [[UIVisualEffectView alloc] initWithEffect:effect];
    _panel.layer.cornerRadius = 16;
    _panel.layer.borderWidth = 0.5;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    _panel.clipsToBounds = YES;
    _panel.hidden = YES;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:_panel];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"CXExamAI";
    title.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    title.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];

    _hintLabel = [[UILabel alloc] init];
    _hintLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _hintLabel.font = [UIFont systemFontOfSize:11];
    _hintLabel.numberOfLines = 2;
    _hintLabel.text = @"状态：待机 · 双击重答 · 长按设置";
    _hintLabel.textAlignment = NSTextAlignmentRight;

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[title, _hintLabel]];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.distribution = UIStackViewDistributionEqualSpacing;
    head.alignment = UIStackViewAlignmentCenter;

    _qLabel = [[UILabel alloc] init];
    _qLabel.textColor = [UIColor whiteColor];
    _qLabel.font = [UIFont systemFontOfSize:13];
    _qLabel.numberOfLines = 3;
    _qLabel.text = @"等待抓题…";

    _answerBox = [[UIView alloc] init];
    _answerBox.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _answerBox.layer.cornerRadius = 10;

    _bigLabel = [[UILabel alloc] init];
    _bigLabel.textColor = [UIColor systemBlueColor];
    _bigLabel.font = [UIFont monospacedSystemFontOfSize:24 weight:UIFontWeightBold];
    _bigLabel.numberOfLines = 1;
    _bigLabel.text = @"";

    _aTextLabel = [[UILabel alloc] init];
    _aTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    _aTextLabel.font = [UIFont systemFontOfSize:13];
    _aTextLabel.numberOfLines = 3;
    _aTextLabel.text = @"";

    [_answerBox addSubview:_bigLabel];
    [_answerBox addSubview:_aTextLabel];
    _bigLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _aTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_bigLabel.topAnchor constraintEqualToAnchor:_answerBox.topAnchor constant:10],
        [_bigLabel.leadingAnchor constraintEqualToAnchor:_answerBox.leadingAnchor constant:12],
        [_bigLabel.trailingAnchor constraintEqualToAnchor:_answerBox.trailingAnchor constant:-12],
        [_aTextLabel.topAnchor constraintEqualToAnchor:_bigLabel.bottomAnchor constant:4],
        [_aTextLabel.leadingAnchor constraintEqualToAnchor:_answerBox.leadingAnchor constant:12],
        [_aTextLabel.trailingAnchor constraintEqualToAnchor:_answerBox.trailingAnchor constant:-12],
        [_aTextLabel.bottomAnchor constraintEqualToAnchor:_answerBox.bottomAnchor constant:-10],
        [_answerBox.heightAnchor constraintGreaterThanOrEqualToConstant:76],
    ]];

    UIButton *again = [UIButton buttonWithType:UIButtonTypeSystem];
    [again setTitle:@"重新作答" forState:UIControlStateNormal];
    [again addTarget:self action:@selector(triggerManual) forControlEvents:UIControlEventTouchUpInside];

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setTitle:@"复制答案" forState:UIControlStateNormal];
    [copy addTarget:self action:@selector(copyAnswer) forControlEvents:UIControlEventTouchUpInside];

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    [settings setTitle:@"设置" forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[again, copy, settings]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    [row.heightAnchor constraintEqualToConstant:34].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[head, _qLabel, _answerBox, row]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel.contentView addSubview:stack];

    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPan:)];
    [_panel addGestureRecognizer:panelPan];

    CGFloat savedTx = [[NSUserDefaults standardUserDefaults] doubleForKey:@"cx_panelTx"];
    CGFloat savedTy = [[NSUserDefaults standardUserDefaults] doubleForKey:@"cx_panelTy"];
    if (savedTx != 0 || savedTy != 0) {
        _panel.transform = CGAffineTransformMakeTranslation(savedTx, savedTy);
    }

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [_panel.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [_panel.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-12],
    ]];
}

- (void)handlePanelPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:_panel.superview];
    _panel.transform = CGAffineTransformTranslate(_panel.transform, t.x, t.y);
    [g setTranslation:CGPointZero inView:_panel.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setDouble:_panel.transform.tx forKey:@"cx_panelTx"];
        [d setDouble:_panel.transform.ty forKey:@"cx_panelTy"];
    }
}

- (void)resetPanelPosition {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_panel.transform = CGAffineTransformIdentity;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setDouble:0 forKey:@"cx_panelTx"];
        [d setDouble:0 forKey:@"cx_panelTy"];
        [[CXHUD shared] setStatus:@"面板位置已重置"];
    });
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
    _bigLabel.text = @"";
    _aTextLabel.text = @"";
}

- (void)copyAnswer {
    NSString *text = [NSString stringWithFormat:@"%@ %@", _bigLabel.text ?: @"", _aTextLabel.text ?: @""];
    if (text.length == 0) return;
    [UIPasteboard generalPasteboard].string = text;
    [[CXHUD shared] setStatus:@"已复制答案"];
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

- (void)setQuestionText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_qLabel) self->_qLabel.text = text;
    });
}

- (void)setStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_hintLabel) return;
        self->_hintLabel.text = [NSString stringWithFormat:@"%@", status ?: @""];
        BOOL bad = [status rangeOfString:@"0题"].location != NSNotFound
                || [status rangeOfString:@"失败"].location != NSNotFound
                || [status rangeOfString:@"错误"].location != NSNotFound
                || [status rangeOfString:@"无响应"].location != NSNotFound
                || [status rangeOfString:@"未注入"].location != NSNotFound
                || [status rangeOfString:@"无WebView"].location != NSNotFound
                || [status rangeOfString:@"缺 Key"].location != NSNotFound;
        UIColor *c = bad ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        self->_ball.backgroundColor = [c colorWithAlphaComponent:0.55];
    });
}

- (void)showAnswer:(NSDictionary *)ans question:(NSString *)stem {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *letters = ans[@"answer"] ?: @[];
        NSString *text = ans[@"text"] ?: @"";
        self->_qLabel.text = stem.length ? stem : @"（未取到题干）";
        self->_bigLabel.text = letters.count ? [letters componentsJoinedByString:@" "] : @"";
        self->_aTextLabel.text = text.length ? text : (letters.count ? @"" : @"（空答案）");
        if ([UIScreen mainScreen].isCaptured) return;
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
