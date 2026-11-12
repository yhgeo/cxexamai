#import "CXCommon.h"

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
    self.apiKey = [d stringForKey:@"cx_key"] ?: @"";
    id autoObj = [d objectForKey:@"cx_auto"];
    self.autoAnswer = autoObj ? [d boolForKey:@"cx_auto"] : YES;
    id guardObj = [d objectForKey:@"cx_guard"];
    self.guardEnabled = guardObj ? [d boolForKey:@"cx_guard"] : YES;
    id hudObj = [d objectForKey:@"cx_hud"];
    self.hudEnabled = hudObj ? [d boolForKey:@"cx_hud"] : YES;
    self.startDelay = [d objectForKey:@"cx_startDelay"] ? [d doubleForKey:@"cx_startDelay"] : 1.5;
    self.gapDelay = [d objectForKey:@"cx_gap"] ? [d doubleForKey:@"cx_gap"] : 2.0;
    id visionObj = [d objectForKey:@"cx_vision"];
    self.visionEnabled = visionObj ? [d boolForKey:@"cx_vision"] : YES;
    self.bankEnabled = [d boolForKey:@"cx_bank_on"];
    self.bankURL = [d stringForKey:@"cx_bank_url"] ?: @"";
    self.bankToken = [d stringForKey:@"cx_bank_token"] ?: @"";
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.baseURL forKey:@"cx_base"];
    [d setObject:self.model forKey:@"cx_model"];
    [d setObject:self.apiKey forKey:@"cx_key"];
    [d setBool:self.autoAnswer forKey:@"cx_auto"];
    [d setBool:self.guardEnabled forKey:@"cx_guard"];
    [d setBool:self.hudEnabled forKey:@"cx_hud"];
    [d setDouble:self.startDelay forKey:@"cx_startDelay"];
    [d setDouble:self.gapDelay forKey:@"cx_gap"];
    [d setBool:self.visionEnabled forKey:@"cx_vision"];
    [d setBool:self.bankEnabled forKey:@"cx_bank_on"];
    [d setObject:self.bankURL ?: @"" forKey:@"cx_bank_url"];
    [d setObject:self.bankToken ?: @"" forKey:@"cx_bank_token"];
    [d synchronize];
}

@end

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
