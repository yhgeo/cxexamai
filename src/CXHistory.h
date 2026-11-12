#import <Foundation/Foundation.h>

/// 本地历史题目与答案，最多保留 100 条
@interface CXHistory : NSObject
+ (instancetype)shared;
- (void)addStem:(NSString *)stem type:(NSString *)type answer:(NSArray *)answer text:(NSString *)text;
- (NSArray<NSDictionary *> *)all;
- (void)clear;
@end
