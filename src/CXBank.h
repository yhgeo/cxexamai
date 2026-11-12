#import <Foundation/Foundation.h>

/// 题库：本地历史优先，其次远程题库（OCS 风格 GET 接口），未命中返回 nil
@interface CXBank : NSObject
+ (void)query:(NSString *)stem type:(NSString *)type options:(NSArray *)options completion:(void (^)(NSDictionary *ans, NSString *source))done;
+ (void)testBank:(void (^)(BOOL ok, NSString *msg))done;
@end
