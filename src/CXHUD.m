#import "CXHUD.h"
#import "CXCommon.h"
#import "CXAI.h"
#import "CXHistory.h"
#import "CXBank.h"

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

#pragma mark - 历史 Cell

@interface CXHistoryCell : UITableViewCell
@property (nonatomic, strong) UILabel *stemLabel;
@property (nonatomic, strong) UILabel *ansLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@end

@implementation CXHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _stemLabel = [UILabel new];
        _stemLabel.font = [UIFont systemFontOfSize:13];
        _stemLabel.numberOfLines = 2;

        _ansLabel = [UILabel new];
        _ansLabel.font = [UIFont boldSystemFontOfSize:15];
        _ansLabel.textColor = [UIColor systemBlueColor];
        _ansLabel.numberOfLines = 1;

        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont systemFontOfSize:11];
        _metaLabel.textColor = [UIColor secondaryLabelColor];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_stemLabel, _ansLabel, _metaLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 3;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

@end

#pragma mark - 设置页

@interface CXSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation CXSettingsViewController {
    UISegmentedControl *_segment;
    UIStackView *_baseStack, *_modelStack, *_logStack, *_historyStack;

    UITextField *_base, *_model, *_key;
    UISwitch *_auto, *_guard, *_hud, *_vision, *_bankOn, *_forceWrite, *_autoFill, *_probe;
    UIScrollView *_scroll;
    UITextField *_bankURL, *_bankToken;
    UITextView *_bankJSONView;
    NSLayoutConstraint *_historyHeight;
    UISlider *_delay;
    UILabel *_delayLabel;
    UILabel *_testLabel;

    UITextView *_logView;
    UILabel *_sizeLabel;

    UITableView *_historyTable;
    NSArray *_historyItems;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [NSString stringWithFormat:@"CXExamAI %@", CX_VERSION];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(save)];

    CXConfig *c = [CXConfig shared];

    _segment = [[UISegmentedControl alloc] initWithItems:@[@"基础", @"模型", @"日志", @"缓存"]];
    _segment.selectedSegmentIndex = 0;
    [_segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    _segment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_segment];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    _scroll = scroll;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [_segment.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [_segment.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_segment.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:_segment.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIStackView *root = [[UIStackView alloc] init];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 0;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [root.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [root.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
        [root.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-40],
    ]];

    // ---------- 基础 ----------
    _baseStack = [self columnStack];
    _auto = [UISwitch new]; _auto.on = c.autoAnswer;
    _guard = [UISwitch new]; _guard.on = c.guardEnabled;
    _hud = [UISwitch new]; _hud.on = c.hudEnabled;
    _vision = [UISwitch new]; _vision.on = c.visionEnabled;

    _autoFill = [UISwitch new];
    _autoFill.on = c.autoFill;
    _forceWrite = [UISwitch new];
    _forceWrite.on = c.forceWrite;
    _probe = [UISwitch new];
    _probe.on = c.probeEnabled;

    _delayLabel = [UILabel new];
    _delayLabel.font = [UIFont systemFontOfSize:14];
    _delayLabel.text = [NSString stringWithFormat:@"开始作答延迟：%.1f 秒", c.startDelay];
    _delay = [UISlider new];
    _delay.minimumValue = 0; _delay.maximumValue = 5; _delay.value = c.startDelay;
    [_delay addTarget:self action:@selector(delayChanged) forControlEvents:UIControlEventValueChanged];

    for (UIView *v in @[[self row:@"自动答题" control:_auto],
                        [self row:@"考试页防检测" control:_guard],
                        [self row:@"显示悬浮球" control:_hud],
                        [self row:@"识别题目图片（需视觉模型）" control:_vision],
                        [self row:@"实验性：自动填答（点选项/填文本）" control:_autoFill],
                        [self row:@"实验性：点击失败时写答案域" control:_forceWrite],
                        [self row:@"调试：原生视图探针（需重启App）" control:_probe],
                        _delayLabel, _delay,
                        [self button:@"重置悬浮窗位置与缩放" action:@selector(resetPanelPos)],
                        [self label:@"面板可拖动、可双指缩放，超出屏幕会自动回弹。"]] ) {
        [_baseStack addArrangedSubview:v];
    }

    // ---------- 模型 ----------
    _modelStack = [self columnStack];
    _base = [self field:@"接口地址，如 https://api.deepseek.com" value:c.baseURL];
    _model = [self field:@"模型名称（填接口实际支持的名称）" value:c.model];
    _key = [self field:@"API Key" value:c.apiKey];
    _key.secureTextEntry = YES;

    _testLabel = [UILabel new];
    _testLabel.font = [UIFont systemFontOfSize:13];
    _testLabel.textColor = [UIColor secondaryLabelColor];
    _testLabel.numberOfLines = 0;

    _bankOn = [UISwitch new];
    _bankOn.on = c.bankEnabled;
    _bankURL = [self field:@"简单模式地址（GET ?question=&type=&token=）" value:c.bankURL];
    _bankToken = [self field:@"简单模式 Token（可选）" value:c.bankToken];

    _bankJSONView = [UITextView new];
    _bankJSONView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _bankJSONView.layer.cornerRadius = 10;
    _bankJSONView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _bankJSONView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    _bankJSONView.text = c.bankJSON;
    [_bankJSONView.heightAnchor constraintEqualToConstant:130].active = YES;

    for (UIView *v in @[_base, _model, _key,
                        [self button:@"测试接口连通" action:@selector(testAPI)],
                        _testLabel,
                        [self label:@"题库（优先于 AI）：把 OCS 的题库 JSON 数组粘到下面即可"],
                        [self row:@"启用题库" control:_bankOn],
                        _bankJSONView,
                        [self button:@"检测题库连通" action:@selector(testBank)],
                        _bankURL, _bankToken,
                        [self label:@"请求格式：GET {地址}?question=题干&type=0/1/2/3&token=xxx；未命中自动转 AI。图片识别会按视觉格式发送 base64，接口不支持时降级纯文本。"]] ) {
        [_modelStack addArrangedSubview:v];
    }

    // ---------- 日志 ----------
    _logStack = [self columnStack];
    _sizeLabel = [UILabel new];
    _sizeLabel.font = [UIFont systemFontOfSize:12];
    _sizeLabel.textColor = [UIColor secondaryLabelColor];

    _logView = [UITextView new];
    _logView.editable = NO;
    _logView.selectable = YES;
    _logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _logView.layer.cornerRadius = 10;
    _logView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [_logView.heightAnchor constraintEqualToConstant:260].active = YES;

    UILabel *pathLabel = [UILabel new];
    pathLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    pathLabel.textColor = [UIColor secondaryLabelColor];
    pathLabel.numberOfLines = 2;
    pathLabel.text = [CXLog path];

    for (UIView *v in @[_sizeLabel,
                        [self button:@"刷新日志" action:@selector(refreshLog)],
                        [self button:@"清理日志与 DOM" action:@selector(cleanupFiles)],
                        [self button:@"导出日志 + DOM 快照" action:@selector(shareLog)],
                        _logView, pathLabel]) {
        [_logStack addArrangedSubview:v];
    }

    // ---------- 历史 ----------
    _historyStack = [self columnStack];
    _historyTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _historyTable.dataSource = self;
    _historyTable.delegate = self;
    _historyTable.rowHeight = 88;
    _historyTable.layer.cornerRadius = 10;
    _historyHeight = [_historyTable.heightAnchor constraintEqualToConstant:380];
    _historyHeight.active = YES;

    for (UIView *v in @[[self label:@"已缓存题目（最近 100 条），点击可复制。"],
                        _historyTable,
                        [self button:@"清空缓存" action:@selector(clearHistory)]]) {
        [_historyStack addArrangedSubview:v];
    }

    for (UIView *v in @[_baseStack, _modelStack, _logStack, _historyStack]) [root addArrangedSubview:v];
    [self segmentChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (UIStackView *)columnStack {
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 12;
    s.layoutMargins = UIEdgeInsetsMake(8, 0, 20, 0);
    s.layoutMarginsRelativeArrangement = YES;
    return s;
}

- (UILabel *)label:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = [UIColor secondaryLabelColor];
    l.numberOfLines = 0;
    return l;
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

- (UIView *)row:(NSString *)title control:(UIView *)control {
    UILabel *l = [UILabel new];
    l.text = title;
    l.font = [UIFont systemFontOfSize:14];
    l.numberOfLines = 2;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    return row;
}

- (UIView *)findFirstResponder:(UIView *)view {
    if (view.isFirstResponder) return view;
    for (UIView *sub in view.subviews) {
        UIView *r = [self findFirstResponder:sub];
        if (r) return r;
    }
    return nil;
}

- (void)keyboardChange:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect inSelf = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(inSelf));
    UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, overlap, 0);
    _scroll.contentInset = inset;
    _scroll.scrollIndicatorInsets = inset;
    if (overlap > 0) {
        UIView *fr = [self findFirstResponder:self.view];
        if (fr) {
            CGRect r = [fr convertRect:fr.bounds toView:_scroll];
            r = CGRectInset(r, 0, -40);
            [_scroll scrollRectToVisible:r animated:YES];
        }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat h = self.view.bounds.size.height - 300;
    _historyHeight.constant = MAX(240, h);
}

- (void)segmentChanged {
    NSInteger i = _segment.selectedSegmentIndex;
    _baseStack.hidden = (i != 0);
    _modelStack.hidden = (i != 1);
    _logStack.hidden = (i != 2);
    _historyStack.hidden = (i != 3);
    if (i == 2) [self refreshLog];
    if (i == 3) [self reloadHistory];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLog];
    [self reloadHistory];
}

- (void)reloadHistory {
    _historyItems = [[CXHistory shared] all];
    [_historyTable reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _historyItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"cxHistoryCell";
    CXHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[CXHistoryCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];

    NSDictionary *item = _historyItems[indexPath.row];
    NSString *stem = item[@"stem"] ?: @"";
    cell.stemLabel.text = stem.length > 70 ? [[stem substringToIndex:70] stringByAppendingString:@"…"] : stem;

    NSString *ans = item[@"ans"] ?: @"";
    cell.ansLabel.text = [NSString stringWithFormat:@"答案  %@", ans.length ? ans : @"（空）"];

    NSTimeInterval ts = [item[@"t"] doubleValue];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    cell.metaLabel.text = [NSString stringWithFormat:@"%@ · %@",
                           [self cnType:item[@"type"] ?: @""],
                           [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]]];
    return cell;
}

- (NSString *)cnType:(NSString *)t {
    if ([t isEqualToString:@"multi"]) return @"多选题";
    if ([t isEqualToString:@"judge"]) return @"判断题";
    if ([t isEqualToString:@"blank"]) return @"填空/简答";
    return @"单选题";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _historyItems[indexPath.row];
    NSString *text = [NSString stringWithFormat:@"%@\n答案：%@", item[@"stem"] ?: @"", item[@"ans"] ?: @""];
    [UIPasteboard generalPasteboard].string = text;
    [[CXHUD shared] setStatus:@"已复制缓存题"];
}

- (void)clearHistory {
    [[CXHistory shared] clear];
    [self reloadHistory];
}

- (void)delayChanged {
    _delayLabel.text = [NSString stringWithFormat:@"开始作答延迟：%.1f 秒", _delay.value];
}

- (void)refreshLog {
    _logView.text = [CXLog tail:80];
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
    _sizeLabel.text = [NSString stringWithFormat:@"日志 %.1f KB · DOM %ld 个 %.1f MB（保留最近 3 个）",
                       sz / 1024.0, (long)domCount, domSize / 1048576.0];
}

- (void)cleanupFiles {
    [CXLog cleanupAll];
    [self refreshLog];
}

- (void)testBank {
    _testLabel.text = @"题库测试中…";
    [CXBank testBank:^(BOOL ok, NSString *msg) {
        self->_testLabel.text = [NSString stringWithFormat:@"题库%@ %@", ok ? @"成功" : @"失败", msg ?: @""];
    }];
}

- (void)resetPanelPos {
    [[CXHUD shared] resetPanelPosition];
}

- (void)save {
    CXConfig *c = [CXConfig shared];
    c.baseURL = _base.text.length ? _base.text : @"https://api.deepseek.com";
    c.model = _model.text.length ? _model.text : c.model;
    c.apiKey = _key.text ?: @"";
    c.autoAnswer = _auto.isOn;
    c.guardEnabled = _guard.isOn;
    c.hudEnabled = _hud.isOn;
    c.visionEnabled = _vision.isOn;
    c.bankEnabled = _bankOn.isOn;
    c.bankURL = _bankURL.text ?: @"";
    c.bankToken = _bankToken.text ?: @"";
    c.forceWrite = _forceWrite.isOn;
    c.autoFill = _autoFill.isOn;
    c.probeEnabled = _probe.isOn;
    c.bankJSON = _bankJSONView.text ?: @"";
    c.startDelay = _delay.value;
    [c save];
    CXLOG(@"设置已保存 model=%@ keyLen=%lu vision=%d", c.model, (unsigned long)c.apiKey.length, c.visionEnabled);
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
    UILabel *_titleLabel;
    UILabel *_qLabel;
    UILabel *_optionsLabel;
    UILabel *_bigLabel;
    UILabel *_aTextLabel;
    UILabel *_hintLabel;
    UIView *_answerBox;
    BOOL _panelShown;
    NSInteger _hideSeq;

    CGFloat _panelTx, _panelTy, _panelScale;
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

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"CXExamAI";
    _titleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];

    _hintLabel = [[UILabel alloc] init];
    _hintLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _hintLabel.font = [UIFont systemFontOfSize:11];
    _hintLabel.numberOfLines = 2;
    _hintLabel.text = @"待机 · 双击重答 · 长按设置";
    _hintLabel.textAlignment = NSTextAlignmentRight;

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _hintLabel]];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.distribution = UIStackViewDistributionEqualSpacing;
    head.alignment = UIStackViewAlignmentCenter;

    _qLabel = [[UILabel alloc] init];
    _qLabel.textColor = [UIColor whiteColor];
    _qLabel.font = [UIFont systemFontOfSize:13];
    _qLabel.numberOfLines = 3;
    _qLabel.text = @"等待抓题…";

    _optionsLabel = [[UILabel alloc] init];
    _optionsLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    _optionsLabel.font = [UIFont systemFontOfSize:11];
    _optionsLabel.numberOfLines = 0;
    _optionsLabel.text = @"";

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

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[head, _qLabel, _optionsLabel, _answerBox, row]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [_panel.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [_panel.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-12],
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPan:)];
    [_panel addGestureRecognizer:pan];
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPinch:)];
    [_panel addGestureRecognizer:pinch];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _panelTx = [d doubleForKey:@"cx_panelTx"];
    _panelTy = [d doubleForKey:@"cx_panelTy"];
    _panelScale = [d objectForKey:@"cx_panelScale"] ? [d doubleForKey:@"cx_panelScale"] : 1.0;
    if (_panelScale < 0.75) _panelScale = 1.0;
    [self applyPanelTransform];
}

- (void)applyPanelTransform {
    CGAffineTransform t = CGAffineTransformMakeTranslation(_panelTx, _panelTy);
    t = CGAffineTransformScale(t, _panelScale, _panelScale);
    _panel.transform = t;
}

- (void)savePanelTransform {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setDouble:_panelTx forKey:@"cx_panelTx"];
    [d setDouble:_panelTy forKey:@"cx_panelTy"];
    [d setDouble:_panelScale forKey:@"cx_panelScale"];
}

- (void)clampPanel {
    CGRect f = _panel.frame;
    CGRect b = _panel.superview.bounds;
    CGFloat dx = 0, dy = 0;
    if (CGRectGetMinX(f) < 4) dx = 4 - CGRectGetMinX(f);
    if (CGRectGetMaxX(f) > b.size.width - 4) dx = b.size.width - 4 - CGRectGetMaxX(f);
    if (CGRectGetMinY(f) < 4) dy = 4 - CGRectGetMinY(f);
    if (CGRectGetMaxY(f) > b.size.height - 4) dy = b.size.height - 4 - CGRectGetMaxY(f);
    if (dx != 0 || dy != 0) {
        _panelTx += dx;
        _panelTy += dy;
        [self applyPanelTransform];
    }
}

- (void)handlePanelPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:_panel.superview];
    _panelTx += t.x;
    _panelTy += t.y;
    [g setTranslation:CGPointZero inView:_panel.superview];
    [self applyPanelTransform];
    if (g.state == UIGestureRecognizerStateEnded) {
        [self clampPanel];
        [self savePanelTransform];
    }
}

- (void)handlePanelPinch:(UIPinchGestureRecognizer *)g {
    CGFloat s = _panelScale * g.scale;
    s = MAX(0.75, MIN(1.5, s));
    _panelScale = s;
    g.scale = 1;
    [self applyPanelTransform];
    if (g.state == UIGestureRecognizerStateEnded) {
        [self clampPanel];
        [self savePanelTransform];
    }
}

- (void)resetPanelPosition {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_panelTx = 0;
        self->_panelTy = 0;
        self->_panelScale = 1.0;
        [self applyPanelTransform];
        [self savePanelTransform];
        [[CXHUD shared] setStatus:@"位置与缩放已重置"];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:_ball.superview];
    CGPoint c = _ball.center;
    _ball.center = CGPointMake(c.x + p.x, c.y + p.y);
    [g setTranslation:CGPointZero inView:_ball.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        CGRect b = _ball.superview.bounds;
        CGPoint cc = _ball.center;
        cc.x = MAX(24, MIN(b.size.width - 24, cc.x));
        cc.y = MAX(24, MIN(b.size.height - 24, cc.y));
        _ball.center = cc;
    }
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
    _optionsLabel.text = @"";
    _optionsLabel.hidden = YES;
    _bigLabel.text = @"";
    _aTextLabel.text = @"";
}

- (void)copyAnswer {
    NSString *opts = _optionsLabel.hidden ? @"" : [NSString stringWithFormat:@"\n选项：\n%@", _optionsLabel.text ?: @""];
    NSString *text = [NSString stringWithFormat:@"%@\n%@%@", _qLabel.text ?: @"", _bigLabel.text ?: @"", opts];
    if (_aTextLabel.text.length > 0) text = [text stringByAppendingFormat:@"\n%@", _aTextLabel.text];
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
        self->_hintLabel.text = status ?: @"";
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

- (void)showAnswer:(NSDictionary *)ans question:(NSString *)stem options:(NSArray *)options source:(NSString *)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *letters = ans[@"answer"] ?: @[];
        NSString *text = ans[@"text"] ?: @"";
        self->_titleLabel.text = [NSString stringWithFormat:@"CXExamAI · %@", source ?: @""];
        self->_qLabel.text = stem.length ? stem : @"（未取到题干）";

        // 选项列表：命中的选项用蓝色加粗高亮，方便核对是否与原题一致
        if ([options isKindOfClass:[NSArray class]] && options.count) {
            NSSet *chosen = [NSSet setWithArray:letters];
            NSMutableAttributedString *optText = [NSMutableAttributedString new];
            for (NSDictionary *o in options) {
                if (![o isKindOfClass:[NSDictionary class]]) continue;
                NSString *k = o[@"k"] ?: @"";
                NSString *t = o[@"t"] ?: @"";
                if (!k.length && !t.length) continue;
                NSString *line = [NSString stringWithFormat:@"%@. %@\n", k, t];
                BOOL hit = [chosen containsObject:k];
                NSDictionary *attr = @{NSForegroundColorAttributeName: hit ? [UIColor systemBlueColor] : [UIColor colorWithWhite:1 alpha:0.78],
                                       NSFontAttributeName: hit ? [UIFont boldSystemFontOfSize:11] : [UIFont systemFontOfSize:11]};
                [optText appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:attr]];
            }
            if (optText.length > 0) {
                // 去掉末尾换行
                [optText deleteCharactersInRange:NSMakeRange(optText.length - 1, 1)];
                self->_optionsLabel.attributedText = optText;
                self->_optionsLabel.hidden = NO;
            } else {
                self->_optionsLabel.text = @"";
                self->_optionsLabel.hidden = YES;
            }
        } else {
            self->_optionsLabel.text = @"";
            self->_optionsLabel.hidden = YES;
        }

        self->_bigLabel.text = letters.count ? [letters componentsJoinedByString:@" "] : @"";
        self->_aTextLabel.text = text.length ? text : (letters.count ? @"" : @"（空答案）");
        if (![CXConfig shared].autoFill) {
            self->_hintLabel.text = @"已出答案 · 仅展示（自动填答关）";
        } else {
            self->_hintLabel.text = letters.count ? @"已出答案，正在点选" : @"已出答案，正在填入";
        }
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
