#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTLog.h>
#import "UnifiedWebrtcView.h"

@interface UnifiedWebrtcViewManager : RCTViewManager
@end

@implementation UnifiedWebrtcViewManager

RCT_EXPORT_MODULE(UnifiedWebrtcView)

- (UIView *)view
{
  return [[UnifiedWebrtcView alloc] init];
}

// Export WebRTC streaming events
RCT_EXPORT_VIEW_PROPERTY(onConnectionStateChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLocalSdpReady, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onRemoteStreamAdded, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onConnectionError, RCTDirectEventBlock)

// Export WebRTC streaming commands
RCT_EXPORT_METHOD(playStream:(nonnull NSNumber *)reactTag streamUrl:(NSString *)streamUrl)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view playStream:streamUrl];
        }
    }];
}

RCT_EXPORT_METHOD(createOffer:(nonnull NSNumber *)reactTag)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view createOffer];
        }
    }];
}

RCT_EXPORT_METHOD(createAnswer:(nonnull NSNumber *)reactTag)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view createAnswer];
        }
    }];
}

RCT_EXPORT_METHOD(setRemoteDescription:(nonnull NSNumber *)reactTag sdp:(NSString *)sdp type:(NSString *)type)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view setRemoteDescription:sdp type:type];
        }
    }];
}

RCT_EXPORT_METHOD(addIceCandidate:(nonnull NSNumber *)reactTag candidateSdp:(NSString *)candidateSdp sdpMLineIndex:(double)sdpMLineIndex sdpMid:(NSString *)sdpMid)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view addIceCandidate:candidateSdp sdpMLineIndex:sdpMLineIndex sdpMid:sdpMid];
        }
    }];
}

RCT_EXPORT_METHOD(dispose:(nonnull NSNumber *)reactTag)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        UnifiedWebrtcView *view = (UnifiedWebrtcView *)viewRegistry[reactTag];
        if (view && [view isKindOfClass:[UnifiedWebrtcView class]]) {
            [view dispose];
        }
    }];
}

@end
