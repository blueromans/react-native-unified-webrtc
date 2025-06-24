#import "UnifiedWebrtcView.h"

#import <react/renderer/components/UnifiedWebrtcViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/EventEmitters.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/Props.h>
#import <react/renderer/components/UnifiedWebrtcViewSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

// Import Jitsi WebRTC framework
#import <JitsiWebRTC/RTCPeerConnectionFactory.h>
#import <JitsiWebRTC/RTCDefaultVideoDecoderFactory.h>
#import <JitsiWebRTC/RTCSoftwareVideoDecoderFactory.h>
#import <JitsiWebRTC/RTCDefaultVideoEncoderFactory.h>
#import <JitsiWebRTC/RTCConfiguration.h>
#import <JitsiWebRTC/RTCIceServer.h>
#import <JitsiWebRTC/RTCMediaConstraints.h>
#import <JitsiWebRTC/RTCVideoRenderer.h>
#import <JitsiWebRTC/RTCEAGLVideoView.h>
#import <AVFoundation/AVFoundation.h>

using namespace facebook::react;

@interface UnifiedWebrtcView () <RCTUnifiedWebrtcViewViewProtocol, RTCPeerConnectionDelegate, RTCVideoViewDelegate>

@property (nonatomic, strong) NSTimer *iceGatheringTimer;
@property (nonatomic, assign) BOOL iceGatheringComplete;
@property (nonatomic, assign) BOOL whepOfferSent;
@property (nonatomic, strong) NSString *pendingStreamUrl;
@property (nonatomic, strong) RTCSessionDescription *localOffer;
@property (nonatomic, strong) NSString *lastEmittedConnectionState;
@property (nonatomic, strong) NSMutableSet<NSString *> *addedVideoTrackIds;

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

    NSLog(@"[UnifiedWebrtcView] Initializing WebRTC for iOS");
    
    // Initialize state variables
    self.iceGatheringComplete = NO;
    self.whepOfferSent = NO;
    self.addedVideoTrackIds = [[NSMutableSet alloc] init];
    
    // Create conditional video decoder factory with H.265 support
    RTCVideoDecoderFactory *decoderFactory = [self createVideoDecoderFactory];
    RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
    
    // Initialize PeerConnectionFactory with conditional codec support
    _peerConnectionFactory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory decoderFactory:decoderFactory];

    // Initialize Video View
    _videoView = [[RTCEAGLVideoView alloc] initWithFrame:self.bounds];
    _videoView.delegate = self;
    [self addSubview:_videoView];
    _videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    NSLog(@"[UnifiedWebrtcView] WebRTC initialization complete for iOS");
  }
  return self;
}

- (RTCVideoDecoderFactory *)createVideoDecoderFactory {
    NSLog(@"[UnifiedWebrtcView] Creating conditional video decoder factory for iOS");
    
    // Check device capabilities for H.265
    BOOL shouldSupportH265 = [self shouldSupportH265];
    
    if (shouldSupportH265) {
        NSLog(@"[UnifiedWebrtcView] Including H.265/HEVC codec (device supports it)");
        // Use default factory which includes H.265 on supported devices
        return [[RTCDefaultVideoDecoderFactory alloc] init];
    } else {
        NSLog(@"[UnifiedWebrtcView] Filtering out H.265/HEVC codec (device doesn't support it)");
        // Create custom factory that excludes H.265
        return [self createFilteredVideoDecoderFactory];
    }
}

- (BOOL)shouldSupportH265 {
    // Check iOS version (H.265 hardware decoding available on iOS 11+, better on iOS 13+)
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    BOOL hasModernIOS = (version.majorVersion >= 13);
    
    // Check if running on simulator
    BOOL isSimulator = [self isRunningOnSimulator];
    
    // Check device capabilities
    BOOL hasHardwareDecoder = [self hasHardwareH265Decoder];
    
    NSLog(@"[UnifiedWebrtcView] H.265 capability check - iOS: %ld.%ld, Simulator: %@, Hardware: %@", 
          (long)version.majorVersion, (long)version.minorVersion, 
          isSimulator ? @"YES" : @"NO", hasHardwareDecoder ? @"YES" : @"NO");
    
    return hasModernIOS && !isSimulator && hasHardwareDecoder;
}

- (BOOL)isRunningOnSimulator {
#if TARGET_OS_SIMULATOR
    return YES;
#else
    return NO;
#endif
}

- (BOOL)hasHardwareH265Decoder {
    // Check if device supports hardware H.265 decoding
    if (@available(iOS 11.0, *)) {
        return [AVAssetReader canReadVideoCodec:AVVideoCodecTypeHEVC];
    }
    return NO;
}

- (RTCVideoDecoderFactory *)createFilteredVideoDecoderFactory {
    // Create a custom decoder factory that excludes H.265
    RTCDefaultVideoDecoderFactory *defaultFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
    
    // Filter out H.265 codecs
    NSArray<RTCVideoCodecInfo *> *supportedCodecs = [defaultFactory supportedCodecs];
    NSMutableArray<RTCVideoCodecInfo *> *filteredCodecs = [[NSMutableArray alloc] init];
    
    for (RTCVideoCodecInfo *codec in supportedCodecs) {
        NSString *codecName = codec.name.uppercaseString;
        if (![codecName isEqualToString:@"H265"] && ![codecName isEqualToString:@"HEVC"]) {
            [filteredCodecs addObject:codec];
        }
    }
    
    NSLog(@"[UnifiedWebrtcView] Filtered codecs: %@", [filteredCodecs valueForKey:@"name"]);
    
    // Return software decoder factory as fallback
    return [[RTCSoftwareVideoDecoderFactory alloc] init];
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

- (NSArray<RTCIceServer *> *)getIceServers {
    return @[
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun.l.google.com:19302"]],
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun1.l.google.com:19302"]],
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun2.l.google.com:19302"]]
    ];
}

- (void)createPeerConnection {
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    config.iceServers = [self getIceServers];
    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;

    _peerConnection = [_peerConnectionFactory peerConnectionWithConfiguration:config
                                                                  constraints:[self defaultMediaConstraints]
                                                                     delegate:self];
    
    // For a viewer, set up transceivers to receive media
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeVideo init:[RTCRtpTransceiverInit new]];
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeAudio init:[RTCRtpTransceiverInit new]];
}

- (void)internalPlayStream:(NSString *)streamUrlOrSignalingInfo {
    NSLog(@"[UnifiedWebrtcView] Starting stream connection to: %@", streamUrlOrSignalingInfo);
    
    // Reset state
    self.iceGatheringComplete = NO;
    self.whepOfferSent = NO;
    self.pendingStreamUrl = streamUrlOrSignalingInfo;
    
    // Cancel any existing timer
    [self.iceGatheringTimer invalidate];
    
    // Check if this is a direct WHEP URL
    if ([streamUrlOrSignalingInfo containsString:@"/whep"]) {
        NSLog(@"[UnifiedWebrtcView] === DIRECT WHEP URL DETECTED ===");
        self.pendingStreamUrl = streamUrlOrSignalingInfo;
        
        if (!_peerConnection) {
            [self createPeerConnection];
        }
        
        // Create offer and wait for ICE gathering completion
        [_peerConnection offerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable offer, NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error creating offer: %@", error.localizedDescription);
                return;
            }
            
            if (offer) {
                NSLog(@"[UnifiedWebrtcView] Local offer created, setting as local description...");
                [self->_peerConnection setLocalDescription:offer completionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error.localizedDescription);
                    } else {
                        NSLog(@"[UnifiedWebrtcView] Local description set. Waiting for ICE gathering...");
                        self.localOffer = offer;
                    }
                }];
            }
        }];
    }
}

- (void)sendWhepOffer:(NSString *)whepUrl {
    if (!self.localOffer) {
        NSLog(@"[UnifiedWebrtcView] No local offer available for WHEP");
        return;
    }
    
    NSLog(@"[UnifiedWebrtcView] === SENDING WHEP OFFER ===");
    NSLog(@"[UnifiedWebrtcView] Sending WHEP offer to: %@", whepUrl);
    NSLog(@"[UnifiedWebrtcView] SDP length: %lu chars", (unsigned long)self.localOffer.sdp.length);
    
    // Create HTTP request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:whepUrl]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/sdp" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/sdp" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:[self.localOffer.sdp dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[UnifiedWebrtcView] WHEP response code: %ld", (long)httpResponse.statusCode);
        
        if (error) {
            NSLog(@"[UnifiedWebrtcView] WHEP request failed: %@", error.localizedDescription);
            [self emitConnectionStateChange:@"error"];
            return;
        }
        
        if (httpResponse.statusCode == 201 && data) {
            NSString *answerSdp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[UnifiedWebrtcView] WHEP answer SDP received: %@", [answerSdp substringToIndex:MIN(100, answerSdp.length)]);
            
            RTCSessionDescription *answer = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeAnswer sdp:answerSdp];
            
            [self->_peerConnection setRemoteDescription:answer completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"[UnifiedWebrtcView] Error setting remote description: %@", error.localizedDescription);
                    [self emitConnectionStateChange:@"error"];
                } else {
                    NSLog(@"[UnifiedWebrtcView] WHEP: Remote description set successfully!");
                    NSLog(@"[UnifiedWebrtcView] WebRTC connection established via WHEP!");
                }
            }];
        } else {
            NSString *errorResponse = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"No response data";
            NSLog(@"[UnifiedWebrtcView] WHEP failed with response code: %ld", (long)httpResponse.statusCode);
            NSLog(@"[UnifiedWebrtcView] WHEP error response: %@", errorResponse);
            [self emitConnectionStateChange:@"error"];
        }
    }];
    
    [task resume];
}

- (void)emitConnectionStateChange:(NSString *)state {
    if ([state isEqualToString:self.lastEmittedConnectionState]) {
        return; // Avoid duplicate emissions
    }
    
    self.lastEmittedConnectionState = state;
    NSLog(@"[UnifiedWebrtcView] Connection state change event emitted: %@", state);
    
    // Emit to React Native
    if (self.eventEmitter) {
        facebook::react::UnifiedWebrtcViewEventEmitter::OnConnectionStateChange event;
        event.state = std::string([state UTF8String]);
        std::static_pointer_cast<const facebook::react::UnifiedWebrtcViewEventEmitter>(self.eventEmitter)->onConnectionStateChange(event);
    }
}

- (void)createOffer {
    if (!_peerConnection) [self createPeerConnection];
    [_peerConnection offerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error creating offer: %@", error.localizedDescription);
            return;
        }
        [self->_peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error.localizedDescription);
            } else {
                NSLog(@"[UnifiedWebrtcView] Offer created and set as local description: %@", sdp.sdp);
                // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
            }
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
            NSLog(@"[UnifiedWebrtcView] Error creating answer: %@", error.localizedDescription);
            return;
        }
        [self->_peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error.localizedDescription);
            } else {
                // Send answer SDP to remote peer
                NSLog(@"[UnifiedWebrtcView] Answer created and set as local description: %@", sdp.sdp);
                // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
            }
        }];
    }];
}

- (void)setRemoteDescriptionWithSdp:(NSString *)sdpString type:(NSString *)typeString {
    if (!_peerConnection) [self createPeerConnection];

    RTCSdpType type = RTCSdpTypeOffer; // Default
    if ([typeString isEqualToString:@"offer"]) {
        type = RTCSdpTypeOffer;
    } else if ([typeString isEqualToString:@"answer"]) {
        type = RTCSdpTypeAnswer;
    }

    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:type sdp:sdpString];
    [_peerConnection setRemoteDescription:sessionDescription completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error setting remote description: %@", error.localizedDescription);
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
    [_peerConnection addIceCandidate:candidate];
    NSLog(@"[UnifiedWebrtcView] ICE candidate added: %@", sdp);
}

- (void)dispose
{
    [self.iceGatheringTimer invalidate];
    self.iceGatheringTimer = nil;
    
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
    _peerConnectionFactory = nil;
}

#pragma mark - RTCPeerConnectionDelegate methods

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)newState {
    NSLog(@"[UnifiedWebrtcView] Signaling state changed: %ld", (long)newState);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {
    NSLog(@"[UnifiedWebrtcView] didAddStream: %@ - DISABLED for crash testing", stream.streamId);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {
    NSLog(@"[UnifiedWebrtcView] didRemoveStream: %@", stream.streamId);
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {
    NSLog(@"[UnifiedWebrtcView] Negotiation needed");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE connection state changed: %ld", (long)newState);
    
    switch (newState) {
        case RTCIceConnectionStateConnected:
            if (![self.lastEmittedConnectionState isEqualToString:@"connected"]) {
                [self emitConnectionStateChange:@"connected"];
            }
            break;
        case RTCIceConnectionStateDisconnected:
            [self emitConnectionStateChange:@"disconnected"];
            break;
        case RTCIceConnectionStateFailed:
            [self emitConnectionStateChange:@"failed"];
            break;
        default:
            break;
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE gathering state: %ld", (long)newState);
    
    switch (newState) {
        case RTCIceGatheringStateGathering:
            // Start timeout timer for ICE gathering (max 3 seconds)
            self.iceGatheringTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
                if (!self.iceGatheringComplete && !self.whepOfferSent) {
                    NSLog(@"[UnifiedWebrtcView] ICE gathering timeout reached, proceeding with available candidates");
                    self.iceGatheringComplete = YES;
                    self.whepOfferSent = YES;
                    if (self.pendingStreamUrl && [self.pendingStreamUrl containsString:@"/whep"]) {
                        [self sendWhepOffer:self.pendingStreamUrl];
                    }
                }
            }];
            break;
            
        case RTCIceGatheringStateComplete:
            // Cancel timeout since gathering completed normally
            [self.iceGatheringTimer invalidate];
            self.iceGatheringTimer = nil;
            
            // ICE gathering complete - ready to send offer for WHEP
            self.iceGatheringComplete = YES;
            if (!self.whepOfferSent) {
                self.whepOfferSent = YES;
                if (self.pendingStreamUrl && [self.pendingStreamUrl containsString:@"/whep"]) {
                    [self sendWhepOffer:self.pendingStreamUrl];
                }
            } else {
                NSLog(@"[UnifiedWebrtcView] WHEP offer already sent, skipping duplicate");
            }
            break;
            
        default:
            break;
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate {
    NSLog(@"[UnifiedWebrtcView] Generated ICE candidate: %@", candidate.sdp);
    // Send candidate to remote peer via signaling server
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
        NSString *trackId = [NSString stringWithFormat:@"%@_%@", mediaStreams.firstObject.streamId, track.trackId];
        
        if (![self.addedVideoTrackIds containsObject:trackId]) {
            [self.addedVideoTrackIds addObject:trackId];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[UnifiedWebrtcView] Adding video track to renderer: %@", trackId);
                self.remoteVideoTrack = (RTCVideoTrack *)track;
                [self.remoteVideoTrack addRenderer:self.videoView];
                NSLog(@"[UnifiedWebrtcView] Video track successfully added: %@", trackId);
            });
        } else {
            NSLog(@"[UnifiedWebrtcView] Video track already added, skipping: %@", trackId);
        }
    }
}

#pragma mark - RTCVideoViewDelegate methods

- (void)videoView:(id<RTCVideoRenderer>)videoView didChangeVideoSize:(CGSize)size {
    NSLog(@"[UnifiedWebrtcView] Video size changed: %fx%f", size.width, size.height);
}

#pragma mark - RCTUnifiedWebrtcViewViewProtocol Command Handlers

- (void)playStream:(NSString *)streamUrlOrSignalingInfo {
    NSLog(@"[UnifiedWebrtcView] Command: playStream called with URL: %@", streamUrlOrSignalingInfo);
    [self internalPlayStream:streamUrlOrSignalingInfo];
}

- (void)createOffer {
    NSLog(@"[UnifiedWebrtcView] Command: createOffer called");
    if (!_peerConnection) [self createPeerConnection];
    [_peerConnection offerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error creating offer: %@", error.localizedDescription);
            return;
        }
        [self->_peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error.localizedDescription);
            } else {
                NSLog(@"[UnifiedWebrtcView] Offer created and set as local description: %@", sdp.sdp);
                // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
            }
        }];
    }];
}

- (void)createAnswer {
    NSLog(@"[UnifiedWebrtcView] Command: createAnswer called");
    if (!_peerConnection) [self createPeerConnection];
    [_peerConnection answerForConstraints:[self defaultMediaConstraints] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error creating answer: %@", error.localizedDescription);
            return;
        }
        [self->_peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Error setting local description: %@", error.localizedDescription);
            } else {
                NSLog(@"[UnifiedWebrtcView] Answer created and set as local description: %@", sdp.sdp);
                // This would be an event to JS: onLocalSdp(sdp.sdp, sdp.typeString)
            }
        }];
    }];
}

- (void)setRemoteDescription:(NSString *)sdp type:(NSString *)type {
    NSLog(@"[UnifiedWebrtcView] Command: setRemoteDescription called with type: %@", type);
    RTCSdpType sdpType = RTCSdpTypeOffer; // Default
    if ([type isEqualToString:@"answer"]) {
        sdpType = RTCSdpTypeAnswer;
    }
    
    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdp];
    [_peerConnection setRemoteDescription:sessionDescription completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Error setting remote description: %@", error.localizedDescription);
        } else {
            NSLog(@"[UnifiedWebrtcView] Remote description set successfully");
        }
    }];
}

- (void)addIceCandidate:(NSString *)candidateSdp sdpMLineIndex:(NSNumber *)sdpMLineIndex sdpMid:(NSString *)sdpMid {
    NSLog(@"[UnifiedWebrtcView] Command: addIceCandidate called");
    RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:candidateSdp sdpMLineIndex:(int)sdpMLineIndex.intValue sdpMid:sdpMid];
    [_peerConnection addIceCandidate:candidate];
}

- (void)dispose {
    NSLog(@"[UnifiedWebrtcView] Command: dispose called");
    [self.iceGatheringTimer invalidate];
    self.iceGatheringTimer = nil;
    
    if (_peerConnection) {
        [_peerConnection close];
        _peerConnection = nil;
    }
    
    _peerConnectionFactory = nil;
    self.pendingStreamUrl = nil;
    self.localOffer = nil;
    
    // Remove all video tracks from renderer
    for (NSString *trackId in self.addedVideoTrackIds) {
        NSLog(@"[UnifiedWebrtcView] Removing video track: %@", trackId);
    }
    [self.addedVideoTrackIds removeAllObjects];
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
