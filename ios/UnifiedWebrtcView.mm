#import "UnifiedWebrtcView.h"

#import <react/renderer/components/UnifiedWebrtcViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/EventEmitters.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/Props.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

// Import Google WebRTC using module import syntax
@import WebRTC;
// #import <WebRTC/WebRTC.h> // Original import causing issues with use_frameworks!

using namespace facebook::react;

@interface UnifiedWebrtcView () <RCTUnifiedWebrtcViewViewProtocol, RTCPeerConnectionDelegate, RTCVideoViewDelegate>
// Removed JitsiMeetViewDelegate
@end

@implementation UnifiedWebrtcView {
    // No longer using _view from original template
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<UnifiedWebrtcViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const UnifiedWebrtcViewProps>();
    _props = defaultProps;

    // Initialize PeerConnectionFactory
    RTCDefaultVideoDecoderFactory *decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
    RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
    encoderFactory.preferredCodec = [RTCVideoCodecInfo h264CodecInfo]; // Or other preferred codec

    _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory decoderFactory:decoderFactory];

    // Initialize Video View
    _videoView = [[RTCEAGLVideoView alloc] initWithFrame:self.bounds];
    _videoView.delegate = self;
    [self addSubview:_videoView];
    _videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _videoView.frame = self.bounds;
}


- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &oldViewProps = *std::static_pointer_cast<UnifiedWebrtcViewProps const>(_props);
    const auto &newViewProps = *std::static_pointer_cast<UnifiedWebrtcViewProps const>(props);

    if (oldViewProps.color != newViewProps.color) {
        NSString * colorToConvert = [[NSString alloc] initWithUTF8String: newViewProps.color.c_str()];
        // self.backgroundColor = [self hexStringToColor:colorToConvert]; // Apply to self if needed
    }

    [super updateProps:props oldProps:oldProps];
}

#pragma mark - Public Methods (WebRTC specific)

- (RTCMediaConstraints *)defaultMediaConstraints {
    NSDictionary *mandatoryConstraints = @{
                                           @"OfferToReceiveAudio": @"true",
                                           @"OfferToReceiveVideo": @"true"
                                           };
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                                                              optionalConstraints:nil];
    return constraints;
}

- (void)createPeerConnection {
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    // Add ICE servers (e.g., Google's public STUN server)
    config.iceServers = @[[[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun.l.google.com:19302"]]];
    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan; // Recommended for modern WebRTC

    _peerConnection = [_peerConnectionFactory peerConnectionWithConfiguration:config
                                                                  constraints:[self defaultMediaConstraints]
                                                                     delegate:self];
    
    // For a viewer, set up transceivers to receive media
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeVideo init:[RTCRtpTransceiverInit new]];
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeAudio init:[RTCRtpTransceiverInit new]];

}


- (void)playStream:(NSString *)streamUrlOrSignalingInfo {
    // This is a placeholder. In a real app, this would involve:
    // 1. Connecting to a signaling server using streamUrlOrSignalingInfo.
    // 2. Exchanging SDP (offer/answer) and ICE candidates.
    // For a simple viewer, you'd typically expect to receive an offer.
    NSLog(@"[UnifiedWebrtcView] playStream called with: %@", streamUrlOrSignalingInfo);
    if (!_peerConnection) {
        [self createPeerConnection];
    }
    // If this component is expected to initiate the call (create offer):
    // [self createOffer];
    // Otherwise, it waits for an offer from the remote peer via signaling.
}

- (void)createOffer {
    if (!_peerConnection) [self createPeerConnection];
    [_peerConnection offerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error creating offer: %@", error);
            return;
        }
        [self.peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error);
                return;
            }
            // Send SDP to remote peer via signaling server
            // Example: [self sendSdpToSignalingServer:sdp];
            NSLog(@"[UnifiedWebrtcView] Offer created and set as local description: %@", sdp.sdp);
            // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
        }];
    }];
}

- (void)createAnswer {
     if (!_peerConnection) {
        NSLog(@"[UnifiedWebrtcView] PeerConnection not initialized for createAnswer");
        return;
    }
    [_peerConnection answerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error creating answer: %@", error);
            return;
        }
        [self.peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description (answer): %@", error);
                return;
            }
            // Send answer SDP to remote peer
            NSLog(@"[UnifiedWebrtcView] Answer created and set as local description: %@", sdp.sdp);
            // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
        }];
    }];
}

- (void)setRemoteDescriptionWithSdp:(NSString *)sdpString type:(NSString *)typeString {
    if (!_peerConnection) [self createPeerConnection];

    RTCSdpType type = RTCSdpTypeOffer; // Default
    if ([typeString.lowercaseString isEqualToString:@"offer"]) {
        type = RTCSdpTypeOffer;
    } else if ([typeString.lowercaseString isEqualToString:@"answer"]) {
        type = RTCSdpTypeAnswer;
    } else if ([typeString.lowercaseString isEqualToString:@"pranswer"]) {
        type = RTCSdpTypePrAnswer;
    }

    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdpString];
    [_peerConnection setRemoteDescription:sdp completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error setting remote description: %@", error);
        } else {
            NSLog(@"[UnifiedWebrtcView] Remote description set successfully.");
            // If we received an offer, now create an answer
            if (type == RTCSdpTypeOffer) {
                [self createAnswer];
            }
        }
    }];
}

- (void)addIceCandidateWithSdp:(NSString *)sdp sdpMLineIndex:(int)sdpMLineIndex sdpMid:(NSString *)sdpMid {
    if (!_peerConnection) {
        NSLog(@"[UnifiedWebrtcView] PeerConnection not initialized for addIceCandidate");
        return;
    }
    RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:sdp sdpMLineIndex:sdpMLineIndex sdpMid:sdpMid];
    [_peerConnection addIceCandidate:candidate completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error adding ICE candidate: %@", error);
        } else {
            NSLog(@"[UnifiedWebrtcView] ICE candidate added successfully.");
        }
    }];
}


- (void)dispose
{
    if (_remoteVideoTrack) {
        [_remoteVideoTrack removeRenderer:_videoView];
        _remoteVideoTrack = nil;
    }
    if (_peerConnection) {
        [_peerConnection close];
        _peerConnection = nil;
    }
    _videoView.delegate = nil;
    [_videoView removeFromSuperview];
    _videoView = nil;
    _peerConnectionFactory = nil; // Release factory
}

#pragma mark - RTCPeerConnectionDelegate methods

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)newState {
    NSLog(@"[UnifiedWebrtcView] Signaling state changed: %ld", (long)newState);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {
    // This is deprecated, use didAddReceiver:streams: instead or onTrack
    NSLog(@"[UnifiedWebrtcView] didAddStream: %@", stream.streamId);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {
    // Deprecated
    NSLog(@"[UnifiedWebrtcView] didRemoveStream: %@", stream.streamId);
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {
    NSLog(@"[UnifiedWebrtcView] Negotiation needed");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE connection state changed: %ld", (long)newState);
    // You might want to handle states like Connected, Disconnected, Failed here
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE gathering state changed: %ld", (long)newState);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate {
    NSLog(@"[UnifiedWebrtcView] Generated ICE candidate: %@", candidate.sdp);
    // Send candidate to remote peer via signaling server
    // Example: [self sendIceCandidateToSignalingServer:candidate];
    // This would be an event to JS: onIceCandidate(candidate.sdp, candidate.sdpMLineIndex, candidate.sdpMid)
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {
    NSLog(@"[UnifiedWebrtcView] Removed ICE candidates");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {
    NSLog(@"[UnifiedWebrtcView] Opened data channel");
}

- (void)peerConnection:(RTCPeerConnection *)pc didAddReceiver:(RTCRtpReceiver *)rtpReceiver streams:(NSArray<RTCMediaStream *> *)mediaStreams {
    NSLog(@"[UnifiedWebrtcView] didAddReceiver for streams: %@", mediaStreams);
    RTCMediaStreamTrack *track = rtpReceiver.track;
    if ([track.kind isEqualToString:kRTCMediaStreamTrackKindVideo]) {
        self.remoteVideoTrack = (RTCVideoTrack *)track;
        [self.remoteVideoTrack addRenderer:self.videoView];
        NSLog(@"[UnifiedWebrtcView] Remote video track added to renderer.");
    }
}

#pragma mark - RTCVideoViewDelegate methods

- (void)videoView:(id<RTCVideoRenderer>)videoView didChangeVideoSize:(CGSize)size {
    NSLog(@"[UnifiedWebrtcView] Video size changed: %fx%f", size.width, size.height);
    // You might want to adjust layout or inform JS here
}


#pragma mark - RCTComponentViewProtocol

Class<RCTComponentViewProtocol> UnifiedWebrtcViewCls(void)
{
    return UnifiedWebrtcView.class;
}

#pragma mark - Color Conversion (helper)

- (UIColor *)hexStringToColor:(NSString *)stringToConvert
{
    NSString *noHashString = [stringToConvert stringByReplacingOccurrencesOfString:@"#" withString:@""];
    NSScanner *stringScanner = [NSScanner scannerWithString:noHashString];

    unsigned hex;
    if (![stringScanner scanHexInt:&hex]) return nil;
    int r = (hex >> 16) & 0xFF;
    int g = (hex >> 8) & 0xFF;
    int b = (hex) & 0xFF;

    return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f];
}

- (void)dealloc {
    [self dispose];
}

@end
