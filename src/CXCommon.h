#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define CX_VERSION @"1.7.0"
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
@property (nonatomic, assign) BOOL bankEnabled;    // 题库优先
@property (nonatomic, copy) NSString *bankURL;
@property (nonatomic, copy) NSString *bankToken;
@property (nonatomic, copy) NSString *bankJSON;   // OCS 题库配置（JSON 数组）
@property (nonatomic, assign) BOOL forceWrite;    // 实验性：点击失败时直接写答案域
@property (nonatomic, assign) BOOL autoFill;      // 实验性：自动填答总开关
@property (nonatomic, assign) BOOL probeEnabled;  // 调试：原生视图探针（默认关，避免生产环境 hook）
+ (instancetype)shared;
- (void)reload;
- (void)save;
@end

/// 取当前最顶层控制器（用于弹设置页）
UIViewController *CXTopViewController(void);

/// 题干 + 按字母排序的选项文本 → 指纹字符串。
/// 学习通会打乱选项顺序：只有选项内容跟着字母位次一起变时指纹才变，
/// 这样同题干不同选项不会被当成同一题串答案。
NSString *CXQuestionFP(NSString *stem, NSArray *opts);

/// 把一组答案文本按当前选项列表反查成字母。文本精确/包含匹配当前选项的 t。
/// 学习通选项会乱序，题库/缓存存的字母不可靠，必须用文本做锚点重新定位。
NSArray *CXLettersForTexts(NSArray *texts, NSArray *opts);

/// 把答案字母数组按选项快照转成对应的文本数组（存储缓存时用）。
NSArray *CXTextsForLetters(NSArray *letters, NSArray *opts);

/// API Key 存系统钥匙串，避免 NSUserDefaults 明文落盘被 Filza 直接读到。
@interface CXKeychain : NSObject
+ (NSString *)getStringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (void)deleteKey:(NSString *)key;
@end
