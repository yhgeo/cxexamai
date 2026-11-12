#import "CXNativeProbe.h"
#import "CXCommon.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSMutableDictionary<NSString *, NSValue *> *gOrigSetData;
static NSMutableDictionary<NSString *, NSValue *> *gOrigParse;

static NSString *CXTrim(id obj, NSUInteger max) {
    NSString *s = [NSString stringWithFormat:@"%@", obj];
    if (s.length > max) s = [[s substringToIndex:max] stringByAppendingString:@"…"];
    return s;
}

static void CXSetDataHook(id self, SEL _cmd, id data) {
    NSString *cls = NSStringFromClass([self class]);
    CXLOG(@"[native] %@ setData: %@", cls, CXTrim(data, 1500));
    NSValue *v = gOrigSetData[cls];
    if (v) {
        void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))[v pointerValue];
        if (fn) fn(self, _cmd, data);
    }
}

static id CXParseDataHook(id self, SEL _cmd, id data) {
    NSString *cls = NSStringFromClass([self class]);
    CXLOG(@"[native] %@ parseData: %@", cls, CXTrim(data, 800));
    NSValue *v = gOrigParse[cls];
    if (v) {
        id (*fn)(id, SEL, id) = (id (*)(id, SEL, id))[v pointerValue];
        if (fn) return fn(self, _cmd, data);
    }
    return nil;
}

@implementation CXNativeProbe

+ (void)start {
    gOrigSetData = [NSMutableDictionary dictionary];
    gOrigParse = [NSMutableDictionary dictionary];

    NSArray *names = @[@"TestPageSingleSelectingView",
                       @"TestPageMultipleSelectingView",
                       @"TestPageJudgmentView",
                       @"TestViewController"];
    for (NSString *name in names) {
        Class c = NSClassFromString(name);
        if (!c) {
            CXLOG(@"原生类不存在: %@", name);
            continue;
        }
        CXLOG(@"原生类存在: %@ (super=%@)", name, class_getSuperclass(c));

        SEL setSel = NSSelectorFromString(@"setData:");
        Method m = class_getInstanceMethod(c, setSel);
        if (m) {
            IMP orig = method_getImplementation(m);
            gOrigSetData[name] = [NSValue valueWithPointer:orig];
            if (!class_addMethod(c, setSel, (IMP)CXSetDataHook, method_getTypeEncoding(m))) {
                method_setImplementation(m, (IMP)CXSetDataHook);
            }
        } else {
            CXLOG(@"  %@ 没有 setData:", name);
        }

        SEL parseSel = NSSelectorFromString(@"parseData:");
        Method pm = class_getInstanceMethod(c, parseSel);
        if (pm) {
            IMP orig = method_getImplementation(pm);
            gOrigParse[name] = [NSValue valueWithPointer:orig];
            if (!class_addMethod(c, parseSel, (IMP)CXParseDataHook, method_getTypeEncoding(pm))) {
                method_setImplementation(pm, (IMP)CXParseDataHook);
            }
        }
    }
}

@end
