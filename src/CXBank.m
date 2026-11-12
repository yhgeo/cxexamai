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

+ (NSDictionary *)normalize:(id)obj type:(NSString *)type {
    NSString *s = nil;
    if ([obj isKindOfClass:[NSString class]]) {
        s = obj;
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        id v = obj[@"answer"] ?: obj[@"ans"] ?: obj[@"result"] ?: obj[@"data"];
        if ([v isKindOfClass:[NSString class]]) s = v;
        else if ([v isKindOfClass:[NSArray class]]) s = [v componentsJoinedByString:@","];
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

+ (void)query:(NSString *)stem type:(NSString *)type completion:(void (^)(NSDictionary *))done {
    if (stem.length == 0) { done(nil); return; }

    // 1) 本地历史
    NSDictionary *local = [[CXHistory shared] answerForStem:stem];
    if (local && ([(NSArray *)local[@"answer"] count] || [(NSString *)local[@"text"] length])) {
        CXLOG(@"题库：本地命中");
        done(local);
        return;
    }

    CXConfig *c = [CXConfig shared];
    if (!c.bankEnabled || c.bankURL.length == 0) { done(nil); return; }

    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *sep = [c.bankURL containsString:@"?"] ? @"&" : @"?";
    NSString *urlStr = [NSString stringWithFormat:@"%@%@question=%@&type=%@&token=%@",
                        c.bankURL, sep,
                        [stem stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"",
                        [self typeCode:type],
                        [c.bankToken stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.timeoutInterval = 8;
    req.HTTPMethod = @"GET";

    CXLOG(@"题库查询 type=%@ %@", type, c.bankURL);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || data.length == 0) {
            CXLOG(@"题库请求失败 %@", err.localizedDescription);
            done(nil);
            return;
        }
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

@end
