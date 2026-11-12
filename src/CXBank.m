#import "CXBank.h"
#import "CXCommon.h"
#import "CXHistory.h"

@implementation CXBank

+ (NSString *)typeCode:(NSString *)type {
    if ([type isEqualToString:@"multi"]) return @"1";
    if ([type isEqualToString:@"judge"]) return @"2";
    if ([type isEqualToString:@"blank"]) return @"3";
    return @"0";
}

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

+ (NSDictionary *)normalize:(id)obj type:(NSString *)type {
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
   completion:(void (^)(NSDictionary *))done {
    if (stem.length == 0) { done(nil); return; }

    // 1) 本地历史
    NSDictionary *local = [[CXHistory shared] answerForStem:stem];
    if (local && ([(NSArray *)local[@"answer"] count] || [(NSString *)local[@"text"] length])) {
        CXLOG(@"题库：本地命中");
        done(local);
        return;
    }

    CXConfig *c = [CXConfig shared];
    if (!c.bankEnabled) { done(nil); return; }

    NSDictionary *ocs = [self ocsConfig];
    if (ocs) {
        [self requestOCS:ocs stem:stem type:type options:options completion:done];
        return;
    }
    if (c.bankURL.length == 0) { done(nil); return; }
    [self requestSimple:stem type:type completion:done];
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
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![root isKindOfClass:[NSDictionary class]]) { done(nil); return; }
        id code = root[@"code"];
        BOOL ok = ([code respondsToSelector:@selector(integerValue)] && [code integerValue] == 1)
               || [code isEqual:@"1"] || [code isEqual:@YES];
        if (!ok) {
            NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            CXLOG(@"题库未命中: %@", [raw substringToIndex:MIN((NSUInteger)160, raw.length)]);
            done(nil);
            return;
        }
        NSDictionary *ans = [self normalize:root[@"data"] type:type];
        if (!ans) ans = [self normalize:root type:type];
        CXLOG(@"题库命中 %@", ans ?: @"（无法解析）");
        done(ans);
    }] resume];
}

+ (void)requestSimple:(NSString *)stem type:(NSString *)type completion:(void (^)(NSDictionary *))done {
    CXConfig *c = [CXConfig shared];
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *sep = [c.bankURL containsString:@"?"] ? @"&" : @"?";
    NSString *urlStr = [NSString stringWithFormat:@"%@%@question=%@&type=%@&token=%@",
                        c.bankURL, sep,
                        [stem stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"",
                        [self typeCode:type],
                        [c.bankToken stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 8;
    CXLOG(@"题库 GET %@", c.bankURL);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || data.length == 0) { done(nil); return; }
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *ans = nil;
        if ([root isKindOfClass:[NSDictionary class]]) {
            id payload = root[@"data"] ?: root[@"result"] ?: root[@"answer"];
            ans = [self normalize:payload type:type];
            if (!ans) ans = [self normalize:root type:type];
        } else {
            ans = [self normalize:root type:type];
        }
        CXLOG(@"题库返回 %@", ans ?: @"未命中");
        done(ans);
    }] resume];
}

+ (void)testBank:(void (^)(BOOL, NSString *))done {
    NSArray *opts = @[@{@"k": @"A", @"t": @"1"}, @{@"k": @"B", @"t": @"2"}];
    [self query:@"1+1等于几" type:@"single" options:opts completion:^(NSDictionary *ans) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ans) { done(NO, @"未命中（检查地址/Token/配置）"); return; }
            NSArray *letters = ans[@"answer"];
            NSString *text = ans[@"text"] ?: @"";
            done(YES, [NSString stringWithFormat:@"命中 %@ %@", [letters componentsJoinedByString:@""], text]);
        });
    }];
}

@end
