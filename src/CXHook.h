#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/// 交换实例方法（repl 必须是同签名的既有方法，通常是分类里新增的 cx_ 方法）
BOOL CXSwizzleInstance(Class cls, SEL orig, SEL repl);

/// 交换类方法
BOOL CXSwizzleClass(Class cls, SEL orig, SEL repl);

/// 直接把方法实现替换成 newImp，返回原 IMP（newImp 为 NULL 时只查询）
IMP CXReplaceImp(Class cls, SEL sel, IMP newImp);

/// 运行时列出类的方法名，调试用
NSArray<NSString *> *CXMethodNames(Class cls);
