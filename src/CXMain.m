#import <Foundation/Foundation.h>
#import "CXCommon.h"
#import "CXWeb.h"
#import "CXHUD.h"
#import "CXGuard.h"

__attribute__((constructor))
static void CXEntry(void) {
    @autoreleasepool {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if (![bid isEqualToString:@"com.ssreader.ChaoXingStudy"]) return;

        CXLOG(@"======== CXExamAI 1.0 注入 (%@) ========", bid);
        [CXWeb start];
        [CXGuard start];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[CXHUD shared] install];
            [CXHUD shared].onManualTrigger = ^{ [CXWeb manualTrigger]; };
        });
    }
}
