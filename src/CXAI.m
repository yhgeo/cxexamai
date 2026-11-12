#import "CXAI.h"
#import "CXCommon.h"
#import "CXHUD.h"

static NSString *const kSystemPrompt =
@"你是中国高校在线考试的答题助手。用户会给出一道题（题干+选项+题型）。"
"你必须只输出一个 JSON 对象，不要输出 markdown 代码块、不要解释、不要多余文字。格式："
"{\"answer\":[\"A\"],\"text\":\"填空或简答内容\",\"confidence\":0.0}"
"规则：单选题 answer 只放 1 个选项字母；多选题放全部正确字母；判断题 A=正确、B=错误；"
"填空题/简答题把完整答案写进 text，多个空用 ||| 分隔；answer 与 text 至少填一个。";

@interface CXAI ()
@property (nonatomic, strong) NSMutableSet<NSString *> *inflight;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation CXAI

+ (instancetype)shared {
    static CXAI *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [CXAI new];
        s.inflight = [NSMutableSet set];
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 60;
        c.timeoutIntervalForResource = 90;
        s.session = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

- (NSString *)endpoint {
    NSString *b = [CXConfig shared].baseURL ?: @"";
    b = [b stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (b.length == 0) b = @"https://api.deepseek.com";
    if ([b containsString:@"/chat/completions"]) return b;
    while ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    if ([b hasSuffix:@"/v1"]) return [b stringByAppendingString:@"/chat/completions"];
    return [b stringByAppendingString:@"/v1/chat/completions"];
}

- (NSString *)questionKey:(NSDictionary *)q {
    NSString *stem = q[@"stem"] ?: @"";
    NSNumber *idx = q[@"idx"] ?: @0;
    return [NSString stringWithFormat:@"%lu-%@", (unsigned long)[stem hash], idx];
}

- (void)solve:(NSDictionary *)question inWebView:(WKWebView *)webView {
    if (![question isKindOfClass:[NSDictionary class]]) return;
    NSString *stem = question[@"stem"];
    if (stem.length < 2) return;

    NSString *key = [self questionKey:question];
    @synchronized (self.inflight) {
        if ([self.inflight containsObject:key]) return;
        [self.inflight addObject:key];
    }

    CXConfig *cfg = [CXConfig shared];
    if (cfg.apiKey.length == 0) {
        CXLOG(@"api key 未配置");
        [[CXHUD shared] setStatus:@"未配置 API Key"];
        @synchronized (self.inflight) { [self.inflight removeObject:key]; }
        return;
    }

    NSMutableArray *opts = [NSMutableArray array];
    for (NSDictionary *o in question[@"opts"] ?: @[]) {
        NSString *t = o[@"t"] ?: @"";
        if (t.length) [opts addObject:t];
    }
    NSDictionary *userPayload = @{@"type": question[@"type"] ?: @"single",
                                  @"stem": stem,
                                  @"options": opts};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:userPayload options:0 error:nil];
    NSString *userContent = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];

    NSDictionary *body = @{@"model": cfg.model ?: @"deepseek-chat",
                           @"messages": @[@{@"role": @"system", @"content": kSystemPrompt},
                                          @{@"role": @"user", @"content": userContent}],
                           @"temperature": @0.1,
                           @"max_tokens": @900,
                           @"stream": @NO};
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self endpoint]]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:cfg.apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = bodyData;

    CXLOG(@"请求模型 %@ 题:%@", cfg.model, [stem substringToIndex:MIN((NSUInteger)40, stem.length)]);
    [[CXHUD shared] setStatus:@"思考中…"];

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWV = webView;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        CXAI *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (err || data.length == 0) {
            CXLOG(@"请求失败 %@", err.localizedDescription);
            [[CXHUD shared] setStatus:@"网络失败"];
            @synchronized (strongSelf.inflight) { [strongSelf.inflight removeObject:key]; }
            return;
        }
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *content = nil;
        if ([root isKindOfClass:[NSDictionary class]]) {
            NSArray *choices = root[@"choices"];
            if ([choices isKindOfClass:[NSArray class]] && choices.count) {
                content = choices[0][@"message"][@"content"];
            }
            if (!content) {
                NSString *errMsg = root[@"error"][@"message"] ?: root[@"message"];
                if (errMsg) CXLOG(@"接口返回错误: %@", errMsg);
            }
        }
        if (content.length == 0) {
            NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            CXLOG(@"无法解析响应: %@", [raw substringToIndex:MIN((NSUInteger)200, raw.length)]);
            [[CXHUD shared] setStatus:@"响应异常"];
            @synchronized (strongSelf.inflight) { [strongSelf.inflight removeObject:key]; }
            return;
        }
        NSDictionary *ans = [strongSelf parseAnswer:content];
        CXLOG(@"模型答案 %@", ans);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CXHUD shared] showAnswer:ans question:stem];
            [strongSelf fill:ans question:question webView:weakWV];
            @synchronized (strongSelf.inflight) { [strongSelf.inflight removeObject:key]; }
        });
    }];
    [task resume];
}

- (NSDictionary *)parseAnswer:(NSString *)content {
    NSString *s = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 去掉 ```json ``` 包裹
    if ([s containsString:@"```"]) {
        NSRange r1 = [s rangeOfString:@"```"];
        NSRange r2 = [s rangeOfString:@"```" options:NSBackwardsSearch];
        if (r2.location != NSNotFound && r2.location > r1.location) {
            s = [s substringWithRange:NSMakeRange(r1.location + 3, r2.location - r1.location - 3)];
            if ([s hasPrefix:@"json"]) s = [s substringFromIndex:4];
            s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    NSRange b1 = [s rangeOfString:@"{"];
    NSRange b2 = [s rangeOfString:@"}" options:NSBackwardsSearch];
    if (b1.location != NSNotFound && b2.location != NSNotFound && b2.location > b1.location) {
        NSString *json = [s substringWithRange:NSMakeRange(b1.location, b2.location - b1.location + 1)];
        NSDictionary *d = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([d isKindOfClass:[NSDictionary class]]) {
            id answer = d[@"answer"];
            NSMutableArray *letters = [NSMutableArray array];
            if ([answer isKindOfClass:[NSArray class]]) {
                for (id v in answer) if ([v isKindOfClass:[NSString class]]) [letters addObject:[v uppercaseString]];
            } else if ([answer isKindOfClass:[NSString class]]) {
                for (NSUInteger i = 0; i < [answer length]; i++) {
                    unichar c = [answer characterAtIndex:i];
                    if (c >= 'A' && c <= 'Z') [letters addObject:[NSString stringWithFormat:@"%C", c]];
                }
            }
            NSString *text = d[@"text"];
            if (![text isKindOfClass:[NSString class]]) text = @"";
            if (letters.count == 0 && text.length == 0) {
                // 退化：整段里找孤立大写字母
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\b[A-F]\\b" options:0 error:nil];
                for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
                    [letters addObject:[s substringWithRange:m.range]];
                }
            }
            return @{@"answer": letters, @"text": text};
        }
    }
    return @{@"answer": @[], @"text": s};
}

- (void)fill:(NSDictionary *)ans question:(NSDictionary *)q webView:(WKWebView *)wv {
    if (!wv) return;
    NSNumber *idx = q[@"idx"] ?: @0;
    NSData *ld = [NSJSONSerialization dataWithJSONObject:ans[@"answer"] ?: @[] options:0 error:nil];
    NSData *td = [NSJSONSerialization dataWithJSONObject:@[ans[@"text"] ?: @""] options:0 error:nil];
    NSString *h = q[@"h"] ?: @"";
    NSString *js = [NSString stringWithFormat:@"window.__cxFill&&window.__cxFill(%@,%@,%@,\"%@\");",
                    idx,
                    [[NSString alloc] initWithData:ld encoding:NSUTF8StringEncoding],
                    [[NSString alloc] initWithData:td encoding:NSUTF8StringEncoding],
                    h];
    dispatch_async(dispatch_get_main_queue(), ^{
        [wv evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
            if (e) CXLOG(@"回填失败 %@", e.localizedDescription);
            else CXLOG(@"回填完成 #%@", idx);
            [[CXHUD shared] setStatus:@"已填答"];
        }];
    });
}

- (void)testConnection:(void (^)(BOOL, NSString *))done {
    CXConfig *cfg = [CXConfig shared];
    NSDictionary *body = @{@"model": cfg.model ?: @"deepseek-chat",
                           @"messages": @[@{@"role": @"user", @"content": @"ping"}],
                           @"max_tokens": @8};
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self endpoint]]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:cfg.apiKey ?: @""] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { done(NO, err.localizedDescription); return; }
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            done(code == 200, [NSString stringWithFormat:@"HTTP %ld", (long)code]);
        });
    }] resume];
}

@end
