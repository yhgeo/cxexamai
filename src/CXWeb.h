#import <Foundation/Foundation.h>

/// 注入与页面桥接：所有 WKWebView 自动挂脚本与消息通道
@interface CXWeb : NSObject
+ (void)start;
+ (void)manualTrigger;
@end
