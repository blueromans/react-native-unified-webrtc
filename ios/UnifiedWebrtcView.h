#import <UIKit/UIKit.h>
#import <React/RCTViewComponentView.h>
#import <React/RCTViewManager.h>

// Import WebRTC framework
#import <JitsiWebRTC/JitsiWebRTC.h>

NS_ASSUME_NONNULL_BEGIN

@interface UnifiedWebrtcView : RCTViewComponentView

// WebRTC Core Properties
@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, strong) RTCEAGLVideoView *videoView;

// WebRTC Streaming Events
@property (nonatomic, copy) RCTDirectEventBlock onConnectionStateChange;
@property (nonatomic, copy) RCTDirectEventBlock onLocalSdpReady;
@property (nonatomic, copy) RCTDirectEventBlock onRemoteStreamAdded;
@property (nonatomic, copy) RCTDirectEventBlock onConnectionError;

// WebRTC Streaming Commands
- (void)playStream:(NSString *)streamUrl;
- (void)createOffer;
- (void)createAnswer;
- (void)setRemoteDescription:(NSString *)sdp type:(NSString *)type;
- (void)addIceCandidate:(NSString *)candidateSdp sdpMLineIndex:(double)sdpMLineIndex sdpMid:(NSString *)sdpMid;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
