#import <React/RCTViewManager.h>
// No need for RCTUIManager or RCTBridge imports if not using addUIBlock for commands,
// as Fabric handles command dispatch differently.

@interface UnifiedWebrtcViewManager : RCTViewManager
@end

@implementation UnifiedWebrtcViewManager

RCT_EXPORT_MODULE(UnifiedWebrtcView) // This name must match the JS component name.

// For Fabric Native Components, the -(UIView *)view method should NOT be implemented in the manager.
// The Fabric renderer creates view instances using the component descriptor
// from the native view class (UnifiedWebrtcView.mm).

RCT_EXPORT_VIEW_PROPERTY(color, NSString) // Props are declared here. The actual handling is in UnifiedWebrtcView.mm.

// Commands (e.g., 'join', 'leave') are defined in the component's JavaScript specification
// (UnifiedWebrtcViewNativeComponent.ts) using `codegenNativeCommands`.
// The Fabric infrastructure dispatches these commands to the UnifiedWebrtcView instance.
// UnifiedWebrtcView.mm implements `joinRoom:serverURL:jwt:` and `leaveRoom`.
// These methods must align with what the generated command interface expects.
// The `RCTUnifiedWebrtcViewViewProtocol` conformance in UnifiedWebrtcView.mm handles this.

// Cleanup (like calling `dispose`) is handled in `UnifiedWebrtcView.mm`'s `dealloc` method.

@end
