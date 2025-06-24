#import <React/RCTViewComponentView.h>
#import <UIKit/UIKit.h>
#import <JitsiWebRTC/RTCPeerConnectionFactory.h>
#import <JitsiWebRTC/RTCPeerConnection.h>
#import <JitsiWebRTC/RTCVideoTrack.h>
#import <JitsiWebRTC/RTCVideoView.h>
#import <JitsiWebRTC/RTCSessionDescription.h>
#import <JitsiWebRTC/RTCIceCandidate.h>
#import <JitsiWebRTC/RTCMediaStream.h>
#import <JitsiWebRTC/RTCVideoViewDelegate.h>
#import <JitsiWebRTC/RTCPeerConnectionDelegate.h>

#ifndef UnifiedWebrtcViewNativeComponent_h
#define UnifiedWebrtcViewNativeComponent_h

NS_ASSUME_NONNULL_BEGIN

// Forward declare RTCMediaStream for the property
@class RTCMediaStream;

@interface UnifiedWebrtcView : RCTViewComponentView <RTCPeerConnectionDelegate, RTCVideoViewDelegate>

@property (nonatomic, strong) RTCPeerConnectionFactory *peerConnectionFactory;
@property (nonatomic, strong, nullable) RTCPeerConnection *peerConnection;
@property (nonatomic, strong) RTCEAGLVideoView *videoView; // For rendering video
@property (nonatomic, strong, nullable) RTCVideoTrack *remoteVideoTrack;
// @property (nonatomic, strong, nullable) RTCVideoTrack *localVideoTrack; // If local preview is needed

// Method to initiate stream playback (will involve SDP exchange)
- (void)playStream:(NSString *)streamUrlOrSignalingInfo; // Placeholder for actual signaling
- (void)internalPlayStream:(NSString *)streamUrlOrSignalingInfo; // Internal implementation
- (void)dispose;

// Methods for SDP and ICE candidate handling (called from JS via commands)
- (void)createOffer; // If this view can initiate calls
- (void)createAnswer; // If this view receives calls
- (void)setRemoteDescription:(NSString *)sdp type:(NSString *)type;
- (void)addIceCandidate:(NSString *)candidateSdp sdpMLineIndex:(NSNumber *)sdpMLineIndex sdpMid:(NSString *)sdpMid;

// Conditional H.265 codec support methods
- (RTCVideoDecoderFactory *)createVideoDecoderFactory;
- (BOOL)shouldSupportH265;
- (BOOL)isRunningOnSimulator;
- (BOOL)hasHardwareH265Decoder;
- (RTCVideoDecoderFactory *)createFilteredVideoDecoderFactory;

// WHEP protocol support methods
- (void)sendWhepOffer:(NSString *)whepUrl;
- (void)emitConnectionStateChange:(NSString *)state;
- (NSArray<RTCIceServer *> *)getIceServers;

@end

NS_ASSUME_NONNULL_END

#endif /* UnifiedWebrtcViewNativeComponent_h */
