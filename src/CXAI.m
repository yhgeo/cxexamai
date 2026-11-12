#import "CXAI.h"
#import "CXCommon.h"
#import "CXHUD.h"

static NSString *const kSystemPrompt =
@"你是中国高校在线考试的答题引擎。只输出一个 JSON 对象，不输出解释、不输出 Markdown 代码块。\n"
"输出格式：{\"answer\":[\"A\"],\"text\":\"\",\"confidence\":0.9}\n"
"题型规则：\n"
"1. 单选题：answer 恰好 1 个字母。\n"
"2. 多选题：answer 为 2~4 个字母，按字母升序，必须选全所有正确项。\n"
"3. 判断题：answer 为 [\"A\"] 表示正确，[\"B\"] 表示错误。\n"
"4. 填空题：answer 为空数组，text 为各空答案，多个空用 ||| 分隔，顺序与空位一致。\n"
"5. 简答题/论述题：answer 为空数组，text 为完整答案，分点用 1. 2. 3.。\n"
"6. 信息不足无法判断：{\"answer\":[],\"text\":\"\",\"confidence\":0}\n"
"若题目附带图片（电路图、波形图、几何图等），必须结合图片内容作答。\n"
"题干或选项里的错别字按教材常见表述理解；不要臆造选项字母。";

@interface CXAI ()
@property (nonatomic, strong) NSMutableSet<NSString *> *inflight;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *cache;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation CXAI

+ (instancetype)shared {
    static CXAI *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [CXAI new];
        s.inflight = [NSMutableSet set];
        s.cache = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 60;
        c.timeoutIntervalForResource = 120;
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

- (NSString *)typeNameFor:(NSString *)type {
    if ([type isEqualToString:@"multi"]) return @"多选题";
    if ([type isEqualToString:@"judge"]) return @"判断题";
    if ([type isEqualToString:@"blank"]) return @"填空题或简答题";
    return @"单选题";
}

- (NSString *)requirementFor:(NSString *)type {
    if ([type isEqualToString:@"multi"]) return @"选出全部正确选项，answer 输出 2~4 个字母并升序排列。";
    if ([type isEqualToString:@"judge"]) return @"判断题：A=正确，B=错误，answer 输出一个字母。";
    if ([type isEqualToString:@"blank"]) return @"按空位顺序给出答案，多个空用 ||| 分隔；简答题写在 text 里。";
    return @"只选一个最符合的选项，answer 输出一个字母。";
}

- (NSDictionary *)solvePayloadFor:(NSDictionary *)q {
    NSString *type = q[@"type"] ?: @"single";
    NSString *stem = q[@"stem"] ?: @"";
    if ([type isEqualToString:@"single"] && [stem rangeOfString:@"判断"].location != NSNotFound) type = @"judge";

    NSMutableString *optText = [NSMutableString string];
    for (NSDictionary *o in q[@"opts"] ?: @[]) {
        NSString *k = o[@"k"] ?: @"";
        NSString *t = o[@"t"] ?: @"";
        if (t.length == 0) continue;
        [optText appendFormat:@"%@. %@\n", k, t];
    }
    if (optText.length == 0) [optText appendString:@"（无选项，按填空或简答处理）\n"];

    NSArray *imgs = q[@"imgs"];
    NSString *imgNote = imgs.count ? [NSString stringWithFormat:@"\n【图片】本题附 %lu 张图片，已在消息中提供。", (unsigned long)imgs.count] : @"";

    NSString *content = [NSString stringWithFormat:
                         @"【题型】%@\n【题干】%@\n【选项】\n%@【要求】%@%@",
                         [self typeNameFor:type], stem, optText, [self requirementFor:type], imgNote];
    return @{@"type": type, @"content": content};
}

- (NSString *)cacheKey:(NSDictionary *)q {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[(q[@"stem"] ?: @"") hash]];
}

#pragma mark - 求解

- (void)solve:(NSDictionary *)question inWebView:(WKWebView *)webView frame:(WKFrameInfo *)frame {
    if (![question isKindOfClass:[NSDictionary class]]) return;
    NSString *stem = question[@"stem"];
    if (stem.length < 2) return;

    NSString *key = [self cacheKey:question];
    NSDictionary *cached = self.cache[key];
    if (cached) {
        CXLOG(@"命中缓存，直接回填");
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CXHUD shared] showAnswer:cached question:stem];
            [self fill:cached question:question webView:webView frame:frame];
        });
        return;
    }

    @synchronized (self.inflight) {
        if ([self.inflight containsObject:key]) return;
        [self.inflight addObject:key];
    }

    CXConfig *cfg = [CXConfig shared];
    if (cfg.apiKey.length == 0) {
        CXLOG(@"api key 未配置");
        [[CXHUD shared] setStatus:@"缺 Key"];
        @synchronized (self.inflight) { [self.inflight removeObject:key]; }
        return;
    }

    NSDictionary *payload = [self solvePayloadFor:question];
    CXLOG(@"请求 %@ 题型=%@ 题:%@", cfg.model, payload[@"type"], [stem substringToIndex:MIN((NSUInteger)30, stem.length)]);
    CXLOG(@"prompt: %@", [payload[@"content"] substringToIndex:MIN((NSUInteger)260, [payload[@"content"] length])]);
    [[CXHUD shared] setStatus:@"思考中…"];

    NSArray *imgs = question[@"imgs"];
    if (cfg.visionEnabled && [imgs isKindOfClass:[NSArray class]] && imgs.count) {
        [[CXHUD shared] setStatus:@"下载题图…"];
        CXLOG(@"题目含 %lu 张图，开始下载", (unsigned long)imgs.count);
        __weak typeof(self) weakSelf = self;
        [self fetchImages:imgs completion:^(NSArray<NSString *> *b64List) {
            CXAI *strongSelf = weakSelf;
            if (!strongSelf) return;
            CXLOG(@"图片下载完成 %lu 张", (unsigned long)b64List.count);
            [strongSelf requestPayload:payload images:b64List question:question webView:webView frame:frame key:key];
        }];
    } else {
        [self requestPayload:payload images:@[] question:question webView:webView frame:frame key:key];
    }
}

- (void)fetchImages:(NSArray *)urls completion:(void (^)(NSArray<NSString *> *))done {
    NSMutableArray *out = [NSMutableArray array];
    NSLock *lock = [NSLock new];
    dispatch_group_t group = dispatch_group_create();
    NSInteger maxCount = MIN((NSInteger)urls.count, 3);

    for (NSInteger i = 0; i < maxCount; i++) {
        id item = urls[i];
        if (![item isKindOfClass:[NSString class]]) continue;
        NSURL *url = [NSURL URLWithString:item];
        if (!url) continue;
        dispatch_group_enter(group);
        [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (data.length > 1000 && data.length < 4 * 1024 * 1024) {
                NSString *b64 = [data base64EncodedStringWithOptions:0];
                [lock lock];
                if (out.count < 3) [out addObject:b64];
                [lock unlock];
            }
            dispatch_group_leave(group);
        }] resume];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ done([out copy]); });
}

- (NSArray *)messagesWithPayload:(NSDictionary *)payload images:(NSArray<NSString *> *)images {
    NSMutableArray *msgs = [NSMutableArray array];
    [msgs addObject:@{@"role": @"system", @"content": kSystemPrompt}];

    if (images.count == 0) {
        [msgs addObject:@{@"role": @"user", @"content": payload[@"content"]}];
        return msgs;
    }
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:@{@"type": @"text", @"text": payload[@"content"]}];
    for (NSString *b64 in images) {
        NSString *mime = [b64 hasPrefix:@"iVBOR"] ? @"image/png" : @"image/jpeg";
        NSString *dataURL = [NSString stringWithFormat:@"data:%@;base64,%@", mime, b64];
        [parts addObject:@{@"type": @"image_url", @"image_url": @{@"url": dataURL}}];
    }
    [msgs addObject:@{@"role": @"user", @"content": parts}];
    return msgs;
}

- (void)requestPayload:(NSDictionary *)payload
                images:(NSArray<NSString *> *)images
              question:(NSDictionary *)question
               webView:(WKWebView *)webView
                 frame:(WKFrameInfo *)frame
                   key:(NSString *)key {
    NSArray *messages = [self messagesWithPayload:payload images:images];
    BOOL hasImage = images.count > 0;

    NSDictionary *body = @{@"model": [CXConfig shared].model ?: @"deepseek-chat",
                           @"messages": messages,
                           @"temperature": @0.1,
                           @"max_tokens": @3000,
                           @"stream": @NO};
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self endpoint]]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:[CXConfig shared].apiKey ?: @""] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = bodyData;

    __weak typeof(self) weakSelf = self;
    __weak WKWebView *weakWV = webView;
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        CXAI *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];

        // 带图请求失败：降级为纯文本再试一次
        if (hasImage && (err || code >= 400)) {
            NSString *raw = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            CXLOG(@"带图请求失败 code=%ld %@，降级纯文本", (long)code, [raw substringToIndex:MIN((NSUInteger)120, raw.length)]);
            [strongSelf requestPayload:payload images:@[] question:question webView:weakWV frame:frame key:key];
            return;
        }

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
                NSDictionary *msg = choices[0][@"message"];
                if ([msg isKindOfClass:[NSDictionary class]]) {
                    id c = msg[@"content"];
                    if ([c isKindOfClass:[NSString class]] && [c length]) content = c;
                    if (!content) {
                        id rc = msg[@"reasoning_content"];
                        if ([rc isKindOfClass:[NSString class]] && [rc length]) {
                            CXLOG(@"content 为空，回退 reasoning_content");
                            content = rc;
                        }
                    }
                }
                CXLOG(@"finish_reason=%@", choices[0][@"finish_reason"] ?: @"?");
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
        CXLOG(@"答案 %@", ans);
        if ([ans[@"answer"] count]) strongSelf.cache[key] = ans;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[CXHUD shared] showAnswer:ans question:question[@"stem"]];
            [strongSelf fill:ans question:question webView:weakWV frame:frame];
            @synchronized (strongSelf.inflight) { [strongSelf.inflight removeObject:key]; }
        });
    }] resume];
}

#pragma mark - 解析

- (NSDictionary *)parseAnswer:(NSString *)content {
    NSString *s = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s containsString:@"```"]) {
        NSRange r1 = [s rangeOfString:@"```"];
        NSRange r2 = [s rangeOfString:@"```" options:NSBackwardsSearch];
        if (r2.location != NSNotFound && r2.location > r1.location) {
            s = [s substringWithRange:NSMakeRange(r1.location + 3, r2.location - r1.location - 3)];
            if ([s hasPrefix:@"json"]) s = [s substringFromIndex:4];
            s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    for (NSString *json in [self jsonCandidates:s]) {
        NSDictionary *d = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        if (!d[@"answer"] && !d[@"text"]) continue;

        id answer = d[@"answer"];
        NSMutableArray *letters = [NSMutableArray array];
        if ([answer isKindOfClass:[NSArray class]]) {
            for (id v in answer) {
                if (![v isKindOfClass:[NSString class]]) continue;
                NSString *u = [v uppercaseString];
                for (NSUInteger i = 0; i < u.length; i++) {
                    unichar c = [u characterAtIndex:i];
                    if (c >= 'A' && c <= 'H') [letters addObject:[NSString stringWithFormat:@"%C", c]];
                }
            }
        } else if ([answer isKindOfClass:[NSString class]]) {
            NSString *u = [answer uppercaseString];
            for (NSUInteger i = 0; i < u.length; i++) {
                unichar c = [u characterAtIndex:i];
                if (c >= 'A' && c <= 'H') [letters addObject:[NSString stringWithFormat:@"%C", c]];
            }
        }
        NSArray *uniq = [[NSSet setWithArray:letters] allObjects];
        uniq = [uniq sortedArrayUsingSelector:@selector(compare:)];
        NSString *text = d[@"text"];
        if (![text isKindOfClass:[NSString class]]) text = @"";
        return @{@"answer": uniq, @"text": text};
    }
    return @{@"answer": @[], @"text": @""};
}

- (NSArray<NSString *> *)jsonCandidates:(NSString *)s {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger end = (NSInteger)s.length - 1;
    while (end >= 0 && out.count < 8) {
        if ([s characterAtIndex:end] != '}') { end--; continue; }
        NSInteger depth = 0, start = -1;
        for (NSInteger i = end; i >= 0; i--) {
            unichar c = [s characterAtIndex:i];
            if (c == '}') depth++;
            else if (c == '{') { depth--; if (depth == 0) { start = i; break; } }
        }
        if (start < 0) break;
        [out addObject:[s substringWithRange:NSMakeRange(start, end - start + 1)]];
        end = start - 1;
    }
    return out;
}

#pragma mark - 回填

- (void)fill:(NSDictionary *)ans question:(NSDictionary *)q webView:(WKWebView *)wv frame:(WKFrameInfo *)frame {
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
        void (^done)(id, NSError *) = ^(id r, NSError *e) {
            if (e) CXLOG(@"回填失败 %@", e.localizedDescription);
            else CXLOG(@"回填指令已下发 #%@", idx);
        };
        if (frame) {
            [wv evaluateJavaScript:js inFrame:frame inContentWorld:WKContentWorld.pageWorld completionHandler:done];
        } else {
            [wv evaluateJavaScript:js completionHandler:done];
        }
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
