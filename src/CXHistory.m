#import "CXHistory.h"
#import "CXCommon.h"

static NSString *const kHistoryFile = @"cx-history.json";
static const NSUInteger kMaxItems = 100;

@implementation CXHistory {
    NSMutableArray<NSDictionary *> *_items;
    NSLock *_lock;
}

+ (instancetype)shared {
    static CXHistory *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        s = [CXHistory new];
        s->_lock = [NSLock new];
        [s load];
    });
    return s;
}

- (NSString *)path {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [dir stringByAppendingPathComponent:kHistoryFile];
}

- (void)load {
    NSData *d = [NSData dataWithContentsOfFile:[self path]];
    if (d.length == 0) { _items = [NSMutableArray array]; return; }
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    _items = [obj isKindOfClass:[NSArray class]] ? [obj mutableCopy] : [NSMutableArray array];
}

- (void)save {
    NSData *d = [NSJSONSerialization dataWithJSONObject:_items options:0 error:nil];
    [d writeToFile:[self path] atomically:YES];
}

- (void)addStem:(NSString *)stem options:(NSArray *)options type:(NSString *)type answer:(NSArray *)answer text:(NSString *)text {
    if (stem.length == 0) return;
    [_lock lock];
    if (!_items) [self load];

    NSMutableString *ans = [NSMutableString string];
    if (answer.count) [ans appendString:[answer componentsJoinedByString:@""]];
    if (text.length) {
        if (ans.length) [ans appendString:@" "];
        [ans appendString:text];
    }
    NSDictionary *item = @{@"t": @([[NSDate date] timeIntervalSince1970]),
                           @"type": type ?: @"",
                           @"stem": stem,
                           @"fp": CXQuestionFP(stem, options),
                           @"ans": ans.length ? ans : @"（空）",
                           @"a": answer ?: @[],
                           @"x": text ?: @""};
    [_items insertObject:item atIndex:0];
    while (_items.count > kMaxItems) [_items removeLastObject];
    [self save];
    [_lock unlock];
}

- (NSArray<NSDictionary *> *)all {
    [_lock lock];
    if (!_items) [self load];
    NSArray *copy = [_items copy];
    [_lock unlock];
    return copy;
}

- (NSDictionary *)answerForStem:(NSString *)stem options:(NSArray *)options {
    if (stem.length == 0) return nil;
    NSString *fp = CXQuestionFP(stem, options);
    [_lock lock];
    if (!_items) [self load];
    NSDictionary *hit = nil;
    // 第一轮：新格式按指纹精确匹配（题干+选项内容，选项乱序不会串答案）
    for (NSDictionary *item in _items) {
        NSString *ifp = item[@"fp"];
        if (ifp.length && [ifp isEqualToString:fp]) { hit = item; break; }
    }
    // 第二轮：兼容旧格式缓存（无 fp 字段），仅当题干完全相同才回退命中
    if (!hit) {
        for (NSDictionary *item in _items) {
            if (!item[@"fp"] && [item[@"stem"] isEqualToString:stem]) { hit = item; break; }
        }
    }
    [_lock unlock];
    if (!hit) return nil;
    NSArray *a = hit[@"a"];
    NSString *x = hit[@"x"];
    if (![a isKindOfClass:[NSArray class]]) a = @[];
    if (![x isKindOfClass:[NSString class]]) x = @"";
    if (a.count == 0 && x.length == 0) return nil;
    return @{@"answer": a, @"text": x};
}

- (void)clear {
    [_lock lock];
    _items = [NSMutableArray array];
    [self save];
    [_lock unlock];
}

@end
