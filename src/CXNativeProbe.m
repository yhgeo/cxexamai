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

// hook 装在基类上，但真正进来的是它的子类实例。必须用 superclass 链逐级找
// 注册时保存的原 IMP；只用 [self class] 精确匹配会查不到而吞掉原生方法。
static IMP CXFindOrig(id self, NSDictionary *store) {
    Class c = [self class];
    while (c) {
        NSValue *v = store[NSStringFromClass(c)];
        if (v) return (IMP)[v pointerValue];
        c = class_getSuperclass(c);
    }
    return NULL;
}

static void CXSetDataHook(id self, SEL _cmd, id data) {
    CXLOG(@"[native] %@ setData: %@", NSStringFromClass([self class]), CXTrim(data, 1500));
    IMP fn = CXFindOrig(self, gOrigSetData);
    if (fn) {
        void (*call)(id, SEL, id) = (void (*)(id, SEL, id))fn;
        call(self, _cmd, data);
    }
}

static id CXParseDataHook(id self, SEL _cmd, id data) {
    CXLOG(@"[native] %@ parseData: %@", NSStringFromClass([self class]), CXTrim(data, 800));
    IMP fn = CXFindOrig(self, gOrigParse);
    if (fn) {
        id (*call)(id, SEL, id) = (id (*)(id, SEL, id))fn;
        return call(self, _cmd, data);
    }
    return nil;
}

@implementation CXNativeProbe

+ (void)start {
    if (![CXConfig shared].probeEnabled) {
        CXLOG(@"原生探针未启用（默认关，设置页可开）");
        return;
    }
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
