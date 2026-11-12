#import "CXHook.h"
#import "CXCommon.h"

BOOL CXSwizzleInstance(Class cls, SEL orig, SEL repl) {
    Method m1 = class_getInstanceMethod(cls, orig);
    Method m2 = class_getInstanceMethod(cls, repl);
    if (!m1 || !m2) {
        CXLOG(@"swizzle miss %@ %@ (orig=%p repl=%p)", cls, NSStringFromSelector(orig), m1, m2);
        return NO;
    }
    method_exchangeImplementations(m1, m2);
    return YES;
}

BOOL CXSwizzleClass(Class cls, SEL orig, SEL repl) {
    Class meta = object_getClass(cls);
    Method m1 = class_getClassMethod(cls, orig);
    Method m2 = class_getClassMethod(cls, repl);
    if (!m1 || !m2) {
        CXLOG(@"class swizzle miss %@ %@", cls, NSStringFromSelector(orig));
        return NO;
    }
    (void)meta;
    method_exchangeImplementations(m1, m2);
    return YES;
}

IMP CXReplaceImp(Class cls, SEL sel, IMP newImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    IMP old = method_getImplementation(m);
    if (newImp) method_setImplementation(m, newImp);
    return old;
}

NSArray<NSString *> *CXMethodNames(Class cls) {
    NSMutableArray *arr = [NSMutableArray array];
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        [arr addObject:NSStringFromSelector(method_getName(list[i]))];
    }
    free(list);
    return arr;
}
