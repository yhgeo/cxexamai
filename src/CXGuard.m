#import "CXGuard.h"
#import "CXCommon.h"
#import "CXHook.h"
#import "CXHUD.h"
#import <UIKit/UIKit.h>

@interface UIView (CXGuard)
- (BOOL)cx_drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
@end

@implementation UIView (CXGuard)

- (BOOL)cx_drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)after {
    // 只有接近整屏的抓取才认为是截屏，避免普通离屏渲染把 HUD 抖掉
    CGFloat area = CGRectGetWidth(rect) * CGRectGetHeight(rect);
    if (area > 300 * 300) {
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

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        CXLOG(@"检测到系统截图，隐藏 HUD");
        [[CXHUD shared] hideTemporarily:2.0];
    }];
}

@end
