#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import "RCTBridge.h"

@interface UnifiedWebrtcViewManager : RCTViewManager
@end

@implementation UnifiedWebrtcViewManager

RCT_EXPORT_MODULE(UnifiedWebrtcView)

- (UIView *)view
{
  return [[UIView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(color, NSString)

@end
