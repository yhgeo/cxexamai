#import "CXWeb.h"
#import "CXCommon.h"
#import "CXHook.h"
#import "CXAI.h"
#import "CXHUD.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// xxd -i 生成
extern unsigned char cx_core_js[];
extern unsigned int cx_core_js_len;

static NSHashTable *gWebViews;
static NSHashTable *gExamWebViews;
static NSMutableDictionary *gAnswered;   // hash -> 时间戳
static NSTimeInterval gLastMsgAt = 0;
static char kInstalledKey;

@interface CXWeb (Install)
+ (void)installIntoConfiguration:(WKWebViewConfiguration *)cfg;
+ (void)pruneDOMsInDir:(NSString *)dir keep:(NSUInteger)keep;
+ (NSString *)coreJS;
+ (void)grabIn:(WKWebView *)wv;
@end

#pragma mark - 消息处理

@interface CXMessageHandler : NSObject <WKScriptMessageHandler>
@end

@implementation CXMessageHandler

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    gLastMsgAt = [NSDate date].timeIntervalSince1970;
    id body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSString *type = body[@"t"];
    WKWebView *wv = message.webView;
    if (![type isKindOfClass:[NSString class]]) return;

    if ([type isEqualToString:@"exam"]) {
        BOOL isExam = [body[@"d"] boolValue];
        if (wv && isExam) {
            @synchronized (gExamWebViews) { [gExamWebViews addObject:wv]; }
        }
        CXLOG(@"页面: exam=%@ url=%@", isExam ? @"YES" : @"NO", body[@"u"]);
        return;
    }

    if ([type isEqualToString:@"log"]) {
        CXLOG(@"[js] %@", body[@"d"]);
        return;
    }

    if ([type isEqualToString:@"q"]) {
        NSArray *list = body[@"d"];
        if (![list isKindOfClass:[NSArray class]] || list.count == 0) return;
        CXLOG(@"捕获 %lu 题 url=%@", (unsigned long)list.count, body[@"u"]);

        CXConfig *cfg = [CXConfig shared];
        if (cfg.apiKey.length == 0) {
            [[CXHUD shared] setStatus:@"缺Key"];
            return;
        }
        if (!cfg.autoAnswer) {
            [[CXHUD shared] setStatus:@"待触发"];
            return;
        }

        WKFrameInfo *frame = message.frameInfo;
        NSInteger i = 0;
        for (NSDictionary *q in list) {
            if (![q isKindOfClass:[NSDictionary class]]) continue;
            NSString *stem = q[@"stem"];
            if (stem.length < 2) continue;
            NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)[stem hash]];
            @synchronized (gAnswered) {
                NSNumber *ts = gAnswered[key];
                NSTimeInterval now = [NSDate date].timeIntervalSince1970;
                if (ts && now - ts.doubleValue < 300) continue;   // 5 分钟内不重复答同一题
                gAnswered[key] = @(now);
            }
            double delay = cfg.startDelay + i * cfg.gapDelay;
            i++;
            __weak WKWebView *weakWV = wv;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[CXAI shared] solve:q inWebView:weakWV frame:frame];
            });
        }
        [[CXHUD shared] setStatus:@"作答中"];
        return;
    }

    if ([type isEqualToString:@"filled"]) {
        [[CXHUD shared] setStatus:@"已填答"];
        return;
    }

    if ([type isEqualToString:@"dom"]) {
        NSString *html = body[@"d"];
        if (![html isKindOfClass:[NSString class]] || html.length == 0) return;
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *name = [NSString stringWithFormat:@"cx-dom-%ld.html", (long)[[NSDate date] timeIntervalSince1970]];
        NSString *path = [dir stringByAppendingPathComponent:name];
        [html writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CXLOG(@"DOM 已保存 %@ (%lu bytes)", path, (unsigned long)html.length);
        [CXWeb pruneDOMsInDir:dir keep:3];
        [[CXHUD shared] setStatus:@"已存DOM"];
    }
}

@end

#pragma mark - CXWeb

@implementation CXWeb

+ (void)start {
    gWebViews = [NSHashTable weakObjectsHashTable];
    gExamWebViews = [NSHashTable weakObjectsHashTable];
    gAnswered = [NSMutableDictionary dictionary];

    BOOL a = CXSwizzleInstance([WKWebView class],
                               @selector(initWithFrame:configuration:),
                               @selector(cx_initWithFrame:configuration:));
    BOOL b = CXSwizzleInstance([WKWebView class],
                               @selector(initWithCoder:),
                               @selector(cx_initWithCoder:));
    CXLOG(@"WKWebView hook init=%@ coder=%@", a ? @"ok" : @"miss", b ? @"ok" : @"miss");
}

+ (void)installIntoConfiguration:(WKWebViewConfiguration *)cfg {
    if (!cfg) return;
    WKUserContentController *ucc = cfg.userContentController;
    if (!ucc) {
        ucc = [WKUserContentController new];
        cfg.userContentController = ucc;
    }
    if (objc_getAssociatedObject(ucc, &kInstalledKey)) return;
    objc_setAssociatedObject(ucc, &kInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [ucc addScriptMessageHandler:[CXMessageHandler new] name:@"cxNative"];

    NSString *js = [[NSString alloc] initWithBytes:cx_core_js
                                            length:cx_core_js_len
                                          encoding:NSUTF8StringEncoding];
    if (js.length == 0) {
        CXLOG(@"JS 资源为空，注入失败");
        return;
    }
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                 injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                              forMainFrameOnly:NO];
    [ucc addUserScript:script];
    CXLOG(@"已安装注入脚本 %lu bytes", (unsigned long)js.length);
}

+ (void)pruneDOMsInDir:(NSString *)dir keep:(NSUInteger)keep {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([f hasPrefix:@"cx-dom-"] && [f hasSuffix:@".html"]) [files addObject:f];
    }
    [files sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [b compare:a]; }];
    if (files.count <= keep) return;
    for (NSUInteger i = keep; i < files.count; i++) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:files[i]] error:nil];
    }
}

+ (NSString *)coreJS {
    static NSString *js;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        js = [[NSString alloc] initWithBytes:cx_core_js length:cx_core_js_len encoding:NSUTF8StringEncoding];
    });
    return js ?: @"";
}

+ (void)grabIn:(WKWebView *)wv {
    [wv evaluateJavaScript:@"window.__cxGrab?window.__cxGrab(true):-1" completionHandler:^(id r, NSError *e) {
        if (e) {
            CXLOG(@"grab 执行失败 %@", e.localizedDescription);
            [[CXHUD shared] setStatus:@"JS错误"];
            return;
        }
        CXLOG(@"grab 返回 %@", r);
        NSInteger n = [r respondsToSelector:@selector(integerValue)] ? [r integerValue] : -1;
        if (n < 0) {
            [[CXHUD shared] setStatus:@"JS未注入"];
            [[CXHUD shared] setQuestionText:@"脚本没有注入到页面"];
        } else if (n == 0) {
            [[CXHUD shared] setStatus:@"抓到0题"];
            [[CXHUD shared] setQuestionText:@"页面里没识别到题目，已存 DOM 快照"];
        } else {
            [[CXHUD shared] setStatus:[NSString stringWithFormat:@"抓到%ld题", (long)n]];
            [[CXHUD shared] setQuestionText:@"已抓题，等待模型回答…"];
        }
    }];
}

+ (void)manualTrigger {
    NSArray *list = nil;
    @synchronized (gExamWebViews) { list = gExamWebViews.allObjects; }
    if (list.count == 0) {
        @synchronized (gWebViews) { list = gWebViews.allObjects; }
    }
    if (list.count == 0) {
        CXLOG(@"手动触发：没有捕获到任何 WKWebView（考试页可能不是 H5）");
        [[CXHUD shared] setStatus:@"无WebView"];
        return;
    }
    @synchronized (gAnswered) { [gAnswered removeAllObjects]; }
    CXLOG(@"手动触发：webview %lu 个", (unsigned long)list.count);
    NSTimeInterval before = gLastMsgAt;
    [[CXHUD shared] setStatus:@"抓题中"];

    for (WKWebView *wv in list) {
        CXLOG(@"  url=%@", wv.URL.absoluteString);
        [wv evaluateJavaScript:@"(typeof window.__cxGrab==='function')?'ok':'no'" completionHandler:^(id r, NSError *e) {
            if (e) CXLOG(@"探针失败 %@", e.localizedDescription);
            if ([r isKindOfClass:[NSString class]] && [r isEqualToString:@"ok"]) {
                [self grabIn:wv];
            } else {
                CXLOG(@"JS 未注入，现场补注入");
                [[CXHUD shared] setStatus:@"补注入"];
                [wv evaluateJavaScript:[self coreJS] completionHandler:^(id r2, NSError *e2) {
                    if (e2) CXLOG(@"补注入失败 %@", e2.localizedDescription);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self grabIn:wv];
                    });
                }];
            }
        }];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gLastMsgAt <= before) {
            CXLOG(@"4 秒内没有任何消息回传");
            [[CXHUD shared] setStatus:@"JS无响应"];
        }
    });
}

@end

#pragma mark - WKWebView 分类

@implementation WKWebView (CX)

- (instancetype)cx_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (!configuration) configuration = [WKWebViewConfiguration new];
    [CXWeb installIntoConfiguration:configuration];
    id v = [self cx_initWithFrame:frame configuration:configuration];
    if (v) {
        @synchronized (gWebViews) { [gWebViews addObject:v]; }
        __weak WKWebView *weakV = v;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WKWebView *wv = weakV;
            if (!wv) return;
            [wv evaluateJavaScript:@"(typeof window.__cxCore==='undefined')?0:1" completionHandler:^(id r, NSError *e) {
                if (e) return;
                if ([r integerValue] == 0) {
                    CXLOG(@"延迟补注入 %@", wv.URL.absoluteString);
                    [wv evaluateJavaScript:[CXWeb coreJS] completionHandler:nil];
                }
            }];
        });
    }
    return v;
}

- (instancetype)cx_initWithCoder:(NSCoder *)coder {
    id v = [self cx_initWithCoder:coder];
    if (v) {
        if (self.configuration) [CXWeb installIntoConfiguration:self.configuration];
        @synchronized (gWebViews) { [gWebViews addObject:self]; }
    }
    return v;
}

@end
