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

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        CXLOG(@"检测到系统截图，隐藏 HUD");
        [[CXHUD shared] hideTemporarily:2.0];
    }];
}

@end
