#import <Foundation/Foundation.h>

/// 考试页防护：截屏瞬间隐藏 HUD、系统截图通知
@interface CXGuard : NSObject
+ (void)start;
@end
