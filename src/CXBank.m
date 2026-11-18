#import "CXBank.h"
#import "CXCommon.h"
#import "CXHistory.h"

@implementation CXBank

+ (NSString *)typeCN:(NSString *)type {
    if ([type isEqualToString:@"multi"]) return @"多选题";
    if ([type isEqualToString:@"judge"]) return @"判断题";
    if ([type isEqualToString:@"blank"]) return @"填空题";
    return @"单选题";
}

/// 解析粘贴进来的 OCS 题库配置（数组取第一个）
+ (NSDictionary *)ocsConfig {
    NSString *raw = [CXConfig shared].bankJSON;
    if (raw.length < 10) return nil;
    NSData *d = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    if ([obj isKindOfClass:[NSArray class]] && [(NSArray *)obj count]) {
        id first = [(NSArray *)obj firstObject];
        if ([first isKindOfClass:[NSDictionary class]]) return first;
    }
    return nil;
}

+ (NSDictionary *)normalize:(id)obj type:(NSString *)type options:(NSArray *)options {
    NSString *s = nil;
    if ([obj isKindOfClass:[NSString class]]) {
        s = obj;
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        s = [obj stringValue];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        s = [(NSArray *)obj componentsJoinedByString:@","];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        id v = obj[@"answer"] ?: obj[@"ans"] ?: obj[@"result"] ?: obj[@"data"];
        if ([v isKindOfClass:[NSString class]]) s = v;
        else if ([v isKindOfClass:[NSArray class]]) s = [(NSArray *)v componentsJoinedByString:@","];
    }
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return nil;

    NSString *trim = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trim isEqualToString:@"对"] || [trim isEqualToString:@"正确"] || [trim isEqualToString:@"√"] || [trim isEqualToString:@"T"]) {
        return @{@"answer": @[@"A"], @"text": @""};
    }
    if ([trim isEqualToString:@"错"] || [trim isEqualToString:@"错误"] || [trim isEqualToString:@"×"] || [trim isEqualToString:@"F"]) {
        return @{@"answer": @[@"B"], @"text": @""};
    }

    NSMutableArray *letters = [NSMutableArray array];
    NSString *upper = [trim uppercaseString];
    for (NSUInteger i = 0; i < upper.length; i++) {
        unichar c = [upper characterAtIndex:i];
        if (c >= 'A' && c <= 'H') [letters addObject:[NSString stringWithFormat:@"%C", c]];
    }
    NSArray *uniq = [[NSSet setWithArray:letters] allObjects];
    uniq = [uniq sortedArrayUsingSelector:@selector(compare:)];
    if (uniq.count) return @{@"answer": uniq, @"text": @""};

    // 答案给的是文字（如"德国古典哲学""两点论"），用选项文本反查字母。
    // 先做精确相等；没有精确匹配再退到"足够长的文本 + 单向包含"，避免
    // "1"/"对"这种短文本命中一堆选项导致多选答错。
    if (options.count) {
        NSString *flat = [[trim lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSMutableArray *exact = [NSMutableArray array];
        NSMutableArray *loose = [NSMutableArray array];
        for (NSDictionary *o in options) {
            NSString *k = o[@"k"] ?: @"";
            NSString *t = o[@"t"] ?: @"";
            if (k.length == 0 || t.length == 0) continue;
            NSString *ft = [[t lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (ft.length == 0) continue;
            if ([ft isEqualToString:flat] || [flat isEqualToString:ft]) {
                [exact addObject:k];
            } else if (ft.length >= 4 && flat.length >= 4 &&
                       ([flat containsString:ft] || [ft containsString:flat])) {
                [loose addObject:k];
            }
        }
        NSArray *use = exact.count ? exact : loose;
        if (use.count) {
            NSArray *u2 = [[NSSet setWithArray:use] allObjects];
            u2 = [u2 sortedArrayUsingSelector:@selector(compare:)];
            return @{@"answer": u2, @"text": @""};
        }
    }

    if ([type isEqualToString:@"blank"]) return @{@"answer": @[], @"text": trim};
    return nil;
}

+ (NSString *)optionsText:(NSArray *)opts {
    NSMutableString *s = [NSMutableString string];
    for (NSDictionary *o in opts) {
        NSString *k = o[@"k"] ?: @"";
        NSString *t = o[@"t"] ?: @"";
        if (t.length == 0) continue;
        [s appendFormat:@"%@. %@\n", k, t];
    }
    return s;
}

+ (void)query:(NSString *)stem
         type:(NSString *)type
      options:(NSArray *)options
   completion:(void (^)(NSDictionary *, NSString *))done {
    if (stem.length == 0) { done(nil, nil); return; }

    // 1) 本地历史（按题干+选项指纹匹配，选项乱序不会串答案）
    NSDictionary *local = [[CXHistory shared] answerForStem:stem options:options];
    if (local && ([(NSArray *)local[@"answer"] count] || [(NSString *)local[@"text"] length])) {
        CXLOG(@"题库：本地命中");
        done(local, @"本地缓存");
        return;
    }

    CXConfig *c = [CXConfig shared];
    if (!c.bankEnabled) { done(nil, nil); return; }

    // 只支持 OCS JSON 题库；简单 GET 模式已移除
    NSDictionary *ocs = [self ocsConfig];
    if (!ocs) { done(nil, nil); return; }
    [self requestOCS:ocs stem:stem type:type options:options completion:^(NSDictionary *ans) {
        done(ans, ans ? @"题库" : nil);
    }];
}

+ (void)requestOCS:(NSDictionary *)cfg
              stem:(NSString *)stem
              type:(NSString *)type
           options:(NSArray *)options
        completion:(void (^)(NSDictionary *))done {
    NSString *url = cfg[@"url"];
    if (![url isKindOfClass:[NSString class]] || url.length == 0) { done(nil); return; }
    NSString *method = [cfg[@"method"] isKindOfClass:[NSString class]] ? cfg[@"method"] : @"post";

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.timeoutInterval = 10;
    req.HTTPMethod = [method uppercaseString];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSDictionary *body = @{@"q": stem,
                           @"options": [self optionsText:options],
                           @"type": [self typeCN:type],
                           @"images": @[],
                           @"suggestion_title": @"",
                           @"suggestion_options": @""};
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    CXLOG(@"题库 OCS 请求 %@ %@", req.HTTPMethod, url);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || data.length == 0) {
            CXLOG(@"题库请求失败 %@", err.localizedDescription);
            done(nil);
            return;
        }
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        CXLOG(@"题库原始返回: %@", [raw substringToIndex:MIN((NSUInteger)320, raw.length)]);
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![root isKindOfClass:[NSDictionary class]]) { done(nil); return; }
        id code = root[@"code"];
        BOOL ok = NO;
        if (code == nil || code == [NSNull null]) {
            // 无 code 字段：带 data/answer 就当成功
            ok = (root[@"data"] != nil || root[@"answer"] != nil);
        } else if ([code isKindOfClass:[NSString class]]) {
            NSString *cs = [(NSString *)code lowercaseString];
            ok = ([cs isEqualToString:@"1"] || [cs isEqualToString:@"0"] ||
                  [cs isEqualToString:@"200"] || [cs isEqualToString:@"success"] ||
                  [cs isEqualToString:@"ok"] || [cs isEqualToString:@"true"]);
        } else if ([code respondsToSelector:@selector(integerValue)]) {
            NSInteger ci = [code integerValue];
            ok = (ci == 0 || ci == 1 || ci == 200);
        }
        if (!ok) {
            NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            CXLOG(@"题库未命中: %@", [raw substringToIndex:MIN((NSUInteger)160, raw.length)]);
            done(nil);
            return;
        }
        NSDictionary *ans = [self normalize:root[@"data"] type:type options:options];
        if (!ans) ans = [self normalize:root[@"answer"] type:type options:options];
        if (!ans) ans = [self normalize:root type:type options:options];
        CXLOG(@"题库命中 %@", ans ?: @"（无法解析）");
        done(ans);
    }] resume];
}

+ (void)testBank:(void (^)(BOOL, NSString *))done {
    CXConfig *c = [CXConfig shared];
    NSDictionary *ocs = [self ocsConfig];
    if (!ocs) {
        if (c.bankJSON.length > 10) {
            done(NO, @"JSON 解析失败：检查引号是否为英文、括号是否完整");
        } else {
            done(NO, @"未配置题库：请粘贴 OCS 题库 JSON 数组");
        }
        return;
    }
    if (![ocs[@"url"] isKindOfClass:[NSString class]]) {
        done(NO, @"JSON 里没有 url 字段");
        return;
    }
    NSArray *opts = @[@{@"k": @"A", @"t": @"1"}, @{@"k": @"B", @"t": @"2"}];
    [self query:@"1+1等于几" type:@"single" options:opts completion:^(NSDictionary *ans, NSString *source) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ans) { done(NO, @"请求已发出但未命中（看日志里的题库返回）"); return; }
            NSArray *letters = ans[@"answer"];
            NSString *text = ans[@"text"] ?: @"";
            done(YES, [NSString stringWithFormat:@"%@命中 %@%@", source ?: @"", [letters componentsJoinedByString:@""], text]);
        });
    }];
}

@end
