#import "CXGuard.h"
#import "CXCommon.h"
#import "CXHook.h"
#import "CXHUD.h"
#import "CXWeb.h"
#import <UIKit/UIKit.h>

// 考试期间抑制失焦/进后台通知，阻止学习通向服务端上报"离开考试"。
// 人脸/认证页由 CXWeb inExamPage 放行，避免活体检测卡死。
static BOOL CXShouldBlockLeaveNotification(NSNotificationName name) {
    // 用独立开关，默认关。此方案会篡改系统通知分发，实测可能导致网络异常，
    // 交由用户自己决定是否开启；JS 层防检测不受影响。
    if (![CXConfig shared].leaveGuardEnabled) return NO;
    if (![CXWeb inExamPage]) return NO;
    return [name isEqualToString:UIApplicationWillResignActiveNotification] ||
           [name isEqualToString:UIApplicationDidEnterBackgroundNotification];
}

@interface NSNotificationCenter (CXGuard)
- (void)cx_postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo;
@end

@implementation NSNotificationCenter (CXGuard)
- (void)cx_postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (CXShouldBlockLeaveNotification(name)) {
        CXLOG(@"拦截离场通知 %@（考试页防检测）", name);
        return;
    }
    [self cx_postNotificationName:name object:object userInfo:userInfo];
}
@end

@interface UIView (CXGuard)
- (BOOL)cx_drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
@end

@implementation UIView (CXGuard)

- (BOOL)cx_drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)after {
    // 只有接近整屏的抓取才认为是截屏，避免普通离屏渲染（大图 cell 等）把 HUD 抖掉。
    // 用屏幕面积比例判断，比写死 300×300 更稳，兼容不同机型分辨率。
    CGFloat area = CGRectGetWidth(rect) * CGRectGetHeight(rect);
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat screenArea = screen.width * screen.height;
    CGFloat ratio = screenArea > 0 ? area / screenArea : 0;
    if (ratio > 0.85) {
        [[CXHUD shared] hideNow];
    }
    return [self cx_drawViewHierarchyInRect:rect afterScreenUpdates:after];
}

@end

@implementation CXGuard

+ (void)start {
    BOOL ok = CXSwizzleInstance([UIView class],
                                @selector(drawViewHierarchyInRect:afterScreenUpdates:),
                                @selector(cx_drawViewHierarchyInRect:afterScreenUpdates:));
    CXLOG(@"Guard draw-hook %@", ok ? @"ok" : @"miss");

    // hook 通知中心，考试页拦截失焦/进后台上报
    BOOL ok2 = CXSwizzleInstance([NSNotificationCenter class],
                                 @selector(postNotificationName:object:userInfo:),
                                 @selector(cx_postNotificationName:object:userInfo:));
    CXLOG(@"Guard notification-hook %@", ok2 ? @"ok" : @"miss");

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        CXLOG(@"检测到系统截图，隐藏 HUD");
        [[CXHUD shared] hideTemporarily:2.0];
    }];
}

@end
