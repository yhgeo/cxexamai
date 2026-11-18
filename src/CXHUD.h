#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CXHUD : NSObject
+ (instancetype)shared;
/// 手动触发一次抓题（悬浮球双击）
@property (nonatomic, copy) void (^onManualTrigger)(void);
- (void)install;
- (void)setStatus:(NSString *)status;
- (void)showAnswer:(NSDictionary *)ans question:(NSString *)stem options:(NSArray *)options source:(NSString *)source;
- (void)setQuestionText:(NSString *)text;
- (void)setVisible:(BOOL)visible;
- (void)hideTemporarily:(NSTimeInterval)seconds;
/// 主线程同步隐藏（截屏瞬间用）
- (void)hideNow;
- (void)resetPanelPosition;
@end
