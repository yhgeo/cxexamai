#import "CXCommon.h"
#import <Security/Security.h>

static NSString *const kLogName = @"CXExamAI.log";
static dispatch_queue_t gLogQueue;
static NSDateFormatter *gFmt;

@implementation CXLog

+ (void)initialize {
    if (self == [CXLog class]) {
        gLogQueue = dispatch_queue_create("cx.log", DISPATCH_QUEUE_SERIAL);
        gFmt = [NSDateFormatter new];
        gFmt.dateFormat = @"MM-dd HH:mm:ss.SSS";
    }
}

+ (NSString *)path {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [dir stringByAppendingPathComponent:kLogName];
}

+ (unsigned long long)logSize {
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[self path] error:nil];
    return attr ? [attr fileSize] : 0;
}

+ (void)cleanupAll {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [[self path] stringByDeletingLastPathComponent];
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([f hasPrefix:@"cx-dom-"] && [f hasSuffix:@".html"]) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
        }
    }
    [fm removeItemAtPath:[self path] error:nil];
    CXLOG(@"日志与 DOM 已清理");
}

+ (NSString *)tail:(NSUInteger)lines {
    NSString *s = [NSString stringWithContentsOfFile:[self path] encoding:NSUTF8StringEncoding error:nil];
    if (s.length == 0) return @"（暂无日志）";
    NSArray *arr = [s componentsSeparatedByString:@"\n"];
    if (arr.count > lines) arr = [arr subarrayWithRange:NSMakeRange(arr.count - lines, lines)];
    return [arr componentsJoinedByString:@"\n"];
}

+ (void)write:(NSString *)fmt, ... {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[CX] %@", msg);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [gFmt stringFromDate:[NSDate date]], msg];
    dispatch_async(gLogQueue, ^{
        NSString *p = [self path];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (!fh) {
            [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            unsigned long long sz = [fh offsetInFile];
            [fh closeFile];
            if (sz > 512 * 1024) {
                NSData *d = [NSData dataWithContentsOfFile:p];
                if (d.length > 256 * 1024) {
                    [[d subdataWithRange:NSMakeRange(d.length - 256 * 1024, 256 * 1024)] writeToFile:p atomically:YES];
                }
            }
        } @catch (NSException *e) {
            [fh closeFile];
        }
    });
}

@end

@implementation CXConfig

+ (instancetype)shared {
    static CXConfig *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [CXConfig new]; [s reload]; });
    return s;
}

- (void)reload {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.baseURL = [d stringForKey:@"cx_base"] ?: @"https://api.deepseek.com";
    self.model = [d stringForKey:@"cx_model"] ?: @"deepseek-chat";
    // API Key 优先从钥匙串读；兼容旧版本：若钥匙串为空则从 NSUserDefaults
    // 读旧明文并迁移进钥匙串，随后清除明文。
    NSString *kcKey = [CXKeychain getStringForKey:@"apiKey"];
    if (kcKey.length) {
        self.apiKey = kcKey;
    } else {
        NSString *legacy = [d stringForKey:@"cx_key"] ?: @"";
        self.apiKey = legacy;
        if (legacy.length) {
            [CXKeychain setString:legacy forKey:@"apiKey"];
            [d removeObjectForKey:@"cx_key"];
            [d synchronize];
        }
    }
    id autoObj = [d objectForKey:@"cx_auto"];
    self.autoAnswer = autoObj ? [d boolForKey:@"cx_auto"] : YES;
    id guardObj = [d objectForKey:@"cx_guard"];
    self.guardEnabled = guardObj ? [d boolForKey:@"cx_guard"] : YES;
    self.leaveGuardEnabled = [d boolForKey:@"cx_leave_guard"];  // 默认关
    id hudObj = [d objectForKey:@"cx_hud"];
    self.hudEnabled = hudObj ? [d boolForKey:@"cx_hud"] : YES;
    self.startDelay = [d objectForKey:@"cx_startDelay"] ? [d doubleForKey:@"cx_startDelay"] : 1.5;
    self.gapDelay = [d objectForKey:@"cx_gap"] ? [d doubleForKey:@"cx_gap"] : 2.0;
    id visionObj = [d objectForKey:@"cx_vision"];
    self.visionEnabled = visionObj ? [d boolForKey:@"cx_vision"] : YES;
    self.bankEnabled = [d boolForKey:@"cx_bank_on"];
    self.bankJSON = [d stringForKey:@"cx_bank_json"] ?: @"";
    self.forceWrite = [d boolForKey:@"cx_force_write"];
    self.autoFill = [d boolForKey:@"cx_auto_fill"];
    self.probeEnabled = [d boolForKey:@"cx_probe"];
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.baseURL forKey:@"cx_base"];
    [d setObject:self.model forKey:@"cx_model"];
    // 钥匙串存 Key，NSUserDefaults 不再保留明文
    if (self.apiKey.length) [CXKeychain setString:self.apiKey forKey:@"apiKey"];
    else [CXKeychain deleteKey:@"apiKey"];
    [d removeObjectForKey:@"cx_key"];
    [d setBool:self.autoAnswer forKey:@"cx_auto"];
    [d setBool:self.guardEnabled forKey:@"cx_guard"];
    [d setBool:self.leaveGuardEnabled forKey:@"cx_leave_guard"];
    [d setBool:self.hudEnabled forKey:@"cx_hud"];
    [d setDouble:self.startDelay forKey:@"cx_startDelay"];
    [d setDouble:self.gapDelay forKey:@"cx_gap"];
    [d setBool:self.visionEnabled forKey:@"cx_vision"];
    [d setBool:self.bankEnabled forKey:@"cx_bank_on"];
    [d setObject:self.bankJSON ?: @"" forKey:@"cx_bank_json"];
    [d setBool:self.forceWrite forKey:@"cx_force_write"];
    [d setBool:self.autoFill forKey:@"cx_auto_fill"];
    [d setBool:self.probeEnabled forKey:@"cx_probe"];
    [d synchronize];
}

@end

@implementation CXKeychain

+ (NSString *)getStringForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: @"CXExamAI",
                        (__bridge id)kSecAttrAccount: key,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return nil;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    if (key.length == 0) return;
    NSData *data = [(value ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *base = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService: @"CXExamAI",
                           (__bridge id)kSecAttrAccount: key};
    NSDictionary *attrs = @{(__bridge id)kSecValueData: data,
                            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock};
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)base, NULL);
    if (st == errSecSuccess) {
        SecItemUpdate((__bridge CFDictionaryRef)base, (__bridge CFDictionaryRef)attrs);
    } else if (st == errSecItemNotFound) {
        NSMutableDictionary *add = [base mutableCopy];
        [add addEntriesFromDictionary:attrs];
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

+ (void)deleteKey:(NSString *)key {
    if (key.length == 0) return;
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: @"CXExamAI",
                        (__bridge id)kSecAttrAccount: key};
    SecItemDelete((__bridge CFDictionaryRef)q);
}

@end

NSString *CXQuestionFP(NSString *stem, NSArray *opts) {
    NSMutableString *fp = [NSMutableString stringWithString:stem ?: @""];
    if ([opts isKindOfClass:[NSArray class]] && opts.count) {
        // 按字母 k 排序，让同一套选项无论原始采集顺序如何都得到同一指纹
        NSArray *sorted = [opts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *ka = [a isKindOfClass:[NSDictionary class]] ? (a[@"k"] ?: @"") : @"";
            NSString *kb = [b isKindOfClass:[NSDictionary class]] ? (b[@"k"] ?: @"") : @"";
            return [ka compare:kb];
        }];
        [fp appendString:@"|"];
        for (NSDictionary *o in sorted) {
            if (![o isKindOfClass:[NSDictionary class]]) continue;
            NSString *k = o[@"k"] ?: @"";
            NSString *t = o[@"t"] ?: @"";
            // 只取文本，去掉可能的 A. 前缀噪声，按内容比对
            [fp appendFormat:@"%@=%@;", k, t];
        }
    }
    return [fp copy];
}

static NSString *CXFlatText(id s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    return [[s lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
}

NSArray *CXTextsForLetters(NSArray *letters, NSArray *opts) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *L in letters) {
        if (![L isKindOfClass:[NSString class]]) continue;
        for (NSDictionary *o in opts) {
            if (![o isKindOfClass:[NSDictionary class]]) continue;
            if ([[o[@"k"] uppercaseString] isEqualToString:[L uppercaseString]]) {
                NSString *t = o[@"t"] ?: @"";
                if (t.length) [out addObject:t];
                break;
            }
        }
    }
    return out;
}

NSArray *CXLettersForTexts(NSArray *texts, NSArray *opts) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *text in texts) {
        if (![text isKindOfClass:[NSString class]] || ![text length]) continue;
        NSString *flat = CXFlatText(text);
        NSString *hit = nil;
        // 1) 精确相等
        for (NSDictionary *o in opts) {
            if (![o isKindOfClass:[NSDictionary class]]) continue;
            if ([CXFlatText(o[@"t"]) isEqualToString:flat]) { hit = o[@"k"]; break; }
        }
        // 2) 足够长的单向包含
        if (!hit && flat.length >= 4) {
            for (NSDictionary *o in opts) {
                if (![o isKindOfClass:[NSDictionary class]]) continue;
                NSString *of = CXFlatText(o[@"t"]);
                if (of.length >= 4 && ([of containsString:flat] || [flat containsString:of])) { hit = o[@"k"]; break; }
            }
        }
        if (hit) [out addObject:hit];
    }
    return out;
}

UIViewController *CXTopViewController(void) {
    UIWindow *keyWin = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { keyWin = w; break; }
        }
        if (keyWin) break;
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = keyWin.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:[UITabBarController class]]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}
