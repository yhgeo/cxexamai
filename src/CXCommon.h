#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define CX_VERSION @"1.4.0"
#define CXLOG(...) [CXLog write:__VA_ARGS__]

@interface CXLog : NSObject
+ (void)write:(NSString *)fmt, ...;
+ (NSString *)path;
+ (NSString *)tail:(NSUInteger)lines;
+ (unsigned long long)logSize;
+ (void)cleanupAll;
@end

@interface CXConfig : NSObject
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) BOOL autoAnswer;
@property (nonatomic, assign) BOOL guardEnabled;
@property (nonatomic, assign) BOOL hudEnabled;
@property (nonatomic, assign) double startDelay;   // 检测到题目后多久开始作答
@property (nonatomic, assign) double gapDelay;     // 多题之间的间隔
@property (nonatomic, assign) BOOL visionEnabled;  // 题目含图片时用视觉模型
+ (instancetype)shared;
- (void)reload;
- (void)save;
@end

/// 取当前最顶层控制器（用于弹设置页）
UIViewController *CXTopViewController(void);
