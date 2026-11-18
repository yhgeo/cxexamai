#import <Foundation/Foundation.h>

/// 注入与页面桥接：所有 WKWebView 自动挂脚本与消息通道
@interface CXWeb : NSObject
+ (void)start;
+ (void)manualTrigger;
/// 当前是否有已识别的考试页 WebView（用于原生层反检测判断）
+ (BOOL)inExamPage;
@end
