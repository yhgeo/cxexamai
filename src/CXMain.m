#import <Foundation/Foundation.h>
#import "CXCommon.h"
#import "CXWeb.h"
#import "CXHUD.h"
#import "CXGuard.h"
#import "CXNativeProbe.h"

__attribute__((constructor))
static void CXEntry(void) {
    @autoreleasepool {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if (![bid isEqualToString:@"com.ssreader.ChaoXingStudy"]) return;

        CXLOG(@"======== CXExamAI %@ 注入 (%@) ========", CX_VERSION, bid);
        [CXWeb start];
        [CXGuard start];
        [CXNativeProbe start];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[CXHUD shared] install];
            [CXHUD shared].onManualTrigger = ^{ [CXWeb manualTrigger]; };
        });
    }
}
