#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

/// 单题求解：把题干+选项发给模型，解析出答案后在页面里回填
@interface CXAI : NSObject
+ (instancetype)shared;
- (void)solve:(NSDictionary *)question inWebView:(WKWebView *)webView frame:(WKFrameInfo *)frame;
- (void)testConnection:(void (^)(BOOL ok, NSString *msg))done;
@end
