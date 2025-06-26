#import "UnifiedWebrtcView.h"
#import <JitsiWebRTC/JitsiWebRTC.h>
#import <AVFoundation/AVFoundation.h>

@interface UnifiedWebrtcView () <RTCPeerConnectionDelegate, RTCVideoViewDelegate>

// WebRTC streaming state
@property (nonatomic, strong) NSTimer *iceGatheringTimer;
@property (nonatomic, assign) BOOL iceGatheringComplete;
@property (nonatomic, assign) BOOL whepOfferSent;
@property (nonatomic, strong) NSString *pendingStreamUrl;
@property (nonatomic, strong) RTCSessionDescription *localOffer;
@property (nonatomic, strong) NSString *lastEmittedConnectionState;
@property (nonatomic, strong) NSMutableSet<NSString *> *addedVideoTrackIds;

@end

@implementation UnifiedWebrtcView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        NSLog(@"[UnifiedWebrtcView] Initializing WebRTC streaming for iOS");
        
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
        
        NSLog(@"[UnifiedWebrtcView] WebRTC streaming initialization complete for iOS");
    }
    return self;
}

#pragma mark - Video Decoder Factory with H.265 Support

- (RTCVideoDecoderFactory *)createVideoDecoderFactory {
    NSLog(@"[UnifiedWebrtcView] Creating conditional video decoder factory for iOS");
    
    // Check device capabilities for H.265
    BOOL shouldSupportH265 = [self shouldSupportH265];
    
    if (shouldSupportH265) {
        NSLog(@"[UnifiedWebrtcView] Including H.265/HEVC codec (device supports it)");
        return [[RTCDefaultVideoDecoderFactory alloc] init];
    } else {
        NSLog(@"[UnifiedWebrtcView] Filtering out H.265/HEVC codec (device doesn't support it)");
        return [[RTCSoftwareVideoDecoderFactory alloc] init];
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

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    _videoView.frame = self.bounds;
}

#pragma mark - WebRTC Peer Connection Setup

- (void)createPeerConnection {
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    config.iceServers = [self getIceServers];
    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
    
    // Add ICE timeouts for faster connection
    config.iceConnectionReceivingTimeout = 5000;  // 5 seconds
    config.iceBackupCandidatePairPingInterval = 2000;  // 2 seconds
    
    _peerConnection = [_peerConnectionFactory peerConnectionWithConfiguration:config constraints:[[RTCMediaConstraints alloc] init] delegate:self];
    
    // Add transceivers for receiving video and audio
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeVideo init:[RTCRtpTransceiverInit new]];
    [_peerConnection addTransceiverOfType:RTCRtpMediaTypeAudio init:[RTCRtpTransceiverInit new]];
}

- (NSArray<RTCIceServer *> *)getIceServers {
    return @[
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun.l.google.com:19302"]],
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun1.l.google.com:19302"]],
        [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun2.l.google.com:19302"]]
    ];
}

#pragma mark - WebRTC Streaming Commands

- (void)playStream:(NSString *)streamUrl {
    NSLog(@"[UnifiedWebrtcView] Starting stream connection to: %@", streamUrl);
    
    // Reset state
    self.iceGatheringComplete = NO;
    self.whepOfferSent = NO;
    self.pendingStreamUrl = streamUrl;
    
    // Cancel any existing timer
    [self.iceGatheringTimer invalidate];
    
    // Check if this is a direct WHEP URL
    if ([streamUrl containsString:@"/whep"]) {
        NSLog(@"[UnifiedWebrtcView] === DIRECT WHEP URL DETECTED ===");
        self.pendingStreamUrl = streamUrl;
        
        if (!_peerConnection) {
            [self createPeerConnection];
        }
        
        // Create offer for WHEP
        RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] init];
        [_peerConnection offerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable offer, NSError * _Nullable error) {
            if (error) {
                NSLog(@"[UnifiedWebrtcView] Failed to create offer: %@", error.localizedDescription);
                [self emitConnectionError:[NSString stringWithFormat:@"Failed to create offer: %@", error.localizedDescription]];
            } else if (offer) {
                [self.peerConnection setLocalDescription:offer completionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        NSLog(@"[UnifiedWebrtcView] Failed to set local description: %@", error.localizedDescription);
                        [self emitConnectionError:[NSString stringWithFormat:@"Failed to set local description: %@", error.localizedDescription]];
                    } else {
                        NSLog(@"[UnifiedWebrtcView] Local description set. Waiting for ICE gathering...");
                        self.localOffer = offer;
                        
                        // Start ICE gathering timeout (3 seconds like Android)
                        self.iceGatheringTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(onIceGatheringTimeout) userInfo:nil repeats:NO];
                    }
                }];
            }
        }];
    }
}

- (void)onIceGatheringTimeout {
    NSLog(@"[UnifiedWebrtcView] ICE gathering timeout reached, sending offer with current candidates");
    if (self.pendingStreamUrl && !self.whepOfferSent) {
        [self sendWhepOffer:self.pendingStreamUrl];
    }
}

- (void)sendWhepOffer:(NSString *)whepUrl {
    if (!self.localOffer) {
        NSLog(@"[UnifiedWebrtcView] No local offer available for WHEP");
        return;
    }
    
    NSLog(@"[UnifiedWebrtcView] === SENDING WHEP OFFER ===");
    self.whepOfferSent = YES;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:whepUrl]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/sdp" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/sdp" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:[self.localOffer.sdp dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[UnifiedWebrtcView] WHEP response code: %ld", (long)httpResponse.statusCode);
        
        if (error) {
            NSLog(@"[UnifiedWebrtcView] WHEP request error: %@", error.localizedDescription);
            [self emitConnectionError:[NSString stringWithFormat:@"WHEP request failed: %@", error.localizedDescription]];
        } else if (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) {
            NSString *answerSdp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[UnifiedWebrtcView] WHEP answer SDP received: %@", [answerSdp substringToIndex:MIN(100, answerSdp.length)]);
            
            RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeAnswer sdp:answerSdp];
            [self.peerConnection setRemoteDescription:remoteSdp completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"[UnifiedWebrtcView] WHEP: Set remote description failed: %@", error.localizedDescription);
                    [self emitConnectionError:[NSString stringWithFormat:@"WHEP: Failed to set remote description: %@", error.localizedDescription]];
                } else {
                    NSLog(@"[UnifiedWebrtcView] WHEP: Remote description set successfully!");
                    NSLog(@"[UnifiedWebrtcView] WebRTC connection established via WHEP!");
                    [self emitConnectionStateChange:@"connected"];
                }
            }];
        } else {
            NSString *errorResponse = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"No response data";
            NSLog(@"[UnifiedWebrtcView] WHEP failed with response code: %ld", (long)httpResponse.statusCode);
            NSLog(@"[UnifiedWebrtcView] WHEP error response: %@", errorResponse);
            [self emitConnectionError:[NSString stringWithFormat:@"WHEP failed: HTTP %ld - %@", (long)httpResponse.statusCode, errorResponse]];
        }
    }];
    
    [task resume];
}

- (void)createOffer {
    NSLog(@"[UnifiedWebrtcView] Creating WebRTC offer");
    
    if (!_peerConnection) {
        [self createPeerConnection];
    }

    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] init];
    [_peerConnection offerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Failed to create offer: %@", error.localizedDescription);
            [self emitConnectionError:[NSString stringWithFormat:@"Failed to create offer: %@", error.localizedDescription]];
        } else if (sdp) {
            [self.peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"[UnifiedWebrtcView] Failed to set local description: %@", error.localizedDescription);
                } else {
                    NSLog(@"[UnifiedWebrtcView] Offer created successfully");
                    [self emitLocalSdp:sdp];
                }
            }];
        }
    }];
}

- (void)createAnswer {
    NSLog(@"[UnifiedWebrtcView] Creating WebRTC answer");
    
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] init];
    [_peerConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Failed to create answer: %@", error.localizedDescription);
            [self emitConnectionError:[NSString stringWithFormat:@"Failed to create answer: %@", error.localizedDescription]];
        } else if (sdp) {
            [self.peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"[UnifiedWebrtcView] Failed to set local description: %@", error.localizedDescription);
                } else {
                    NSLog(@"[UnifiedWebrtcView] Answer created successfully");
                    [self emitLocalSdp:sdp];
                }
            }];
        }
    }];
}

- (void)setRemoteDescription:(NSString *)sdp type:(NSString *)type {
    NSLog(@"[UnifiedWebrtcView] Setting remote description: %@", type);
    
    RTCSdpType sdpType;
    if ([type isEqualToString:@"offer"]) {
        sdpType = RTCSdpTypeOffer;
    } else if ([type isEqualToString:@"answer"]) {
        sdpType = RTCSdpTypeAnswer;
    } else {
        NSLog(@"[UnifiedWebrtcView] Unknown SDP type: %@", type);
        return;
    }
    
    RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdp];
    [_peerConnection setRemoteDescription:remoteSdp completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[UnifiedWebrtcView] Failed to set remote description: %@", error.localizedDescription);
            [self emitConnectionError:[NSString stringWithFormat:@"Failed to set remote description: %@", error.localizedDescription]];
        } else {
            NSLog(@"[UnifiedWebrtcView] Remote description set successfully");
        }
    }];
}

- (void)addIceCandidate:(NSString *)candidateSdp sdpMLineIndex:(double)sdpMLineIndex sdpMid:(NSString *)sdpMid {
    NSLog(@"[UnifiedWebrtcView] Adding ICE candidate");
    
    RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:candidateSdp sdpMLineIndex:(int32_t)sdpMLineIndex sdpMid:sdpMid];
    [_peerConnection addIceCandidate:candidate];
}

- (void)dispose {
    NSLog(@"[UnifiedWebrtcView] Disposing WebRTC resources");
    
    // Cancel timers
    [self.iceGatheringTimer invalidate];
    self.iceGatheringTimer = nil;
    
    // Close peer connection
    if (_peerConnection) {
        [_peerConnection close];
        _peerConnection = nil;
    }
    
    // Clear video view
    if (_videoView) {
        [_videoView removeFromSuperview];
        _videoView = nil;
    }
    
    // Clear state
    [self.addedVideoTrackIds removeAllObjects];
    self.localOffer = nil;
    self.pendingStreamUrl = nil;
}

#pragma mark - RTCPeerConnectionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged {
    NSLog(@"[UnifiedWebrtcView] Signaling state changed: %ld", (long)stateChanged);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {
    NSLog(@"[UnifiedWebrtcView] Remote stream added: %@", stream.streamId);
    
    if (stream.videoTracks.count > 0) {
        RTCVideoTrack *videoTrack = stream.videoTracks.firstObject;
        NSString *trackId = [NSString stringWithFormat:@"%@_%@", stream.streamId, videoTrack.trackId];
        
        // Prevent duplicate video track additions
        if (![self.addedVideoTrackIds containsObject:trackId]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized(self.addedVideoTrackIds) {
                    // Double-check to prevent race conditions
                    if (![self.addedVideoTrackIds containsObject:trackId]) {
                        [self.addedVideoTrackIds addObject:trackId];
                        [videoTrack addRenderer:self.videoView];
                        NSLog(@"[UnifiedWebrtcView] Video track added to renderer: %@", trackId);
                        
                        [self emitRemoteStreamAdded:stream.streamId];
                    }
                }
            });
        }
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {
    NSLog(@"[UnifiedWebrtcView] Remote stream removed: %@", stream.streamId);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE connection state changed: %ld", (long)newState);
    
    NSString *stateString = @"unknown";
    switch (newState) {
        case RTCIceConnectionStateNew:
            stateString = @"new";
            break;
        case RTCIceConnectionStateChecking:
            stateString = @"checking";
            break;
        case RTCIceConnectionStateConnected:
            stateString = @"connected";
            break;
        case RTCIceConnectionStateCompleted:
            stateString = @"completed";
            break;
        case RTCIceConnectionStateFailed:
            stateString = @"failed";
            break;
        case RTCIceConnectionStateDisconnected:
            stateString = @"disconnected";
            break;
        case RTCIceConnectionStateClosed:
            stateString = @"closed";
            break;
        case RTCIceConnectionStateCount:
            stateString = @"count";
            break;
    }
    
    [self emitConnectionStateChange:stateString];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
    NSLog(@"[UnifiedWebrtcView] ICE gathering state changed: %ld", (long)newState);
    
    if (newState == RTCIceGatheringStateComplete) {
        self.iceGatheringComplete = YES;
        [self.iceGatheringTimer invalidate];
        
        // If we have a pending WHEP offer and haven't sent it yet, send it now
        if (self.pendingStreamUrl && !self.whepOfferSent) {
            [self sendWhepOffer:self.pendingStreamUrl];
        }
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate {
    NSLog(@"[UnifiedWebrtcView] ICE candidate generated");
    // ICE candidates are automatically added to the local description
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {
    NSLog(@"[UnifiedWebrtcView] ICE candidates removed");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {
    NSLog(@"[UnifiedWebrtcView] Data channel opened");
}

#pragma mark - RTCVideoViewDelegate

- (void)videoView:(RTCVideoRenderer *)videoView didChangeVideoSize:(CGSize)size {
    NSLog(@"[UnifiedWebrtcView] Video size changed: %@", NSStringFromCGSize(size));
}

#pragma mark - Event Emission

- (void)emitConnectionStateChange:(NSString *)state {
    if (self.onConnectionStateChange && ![state isEqualToString:self.lastEmittedConnectionState]) {
        self.lastEmittedConnectionState = state;
        self.onConnectionStateChange(@{@"state": state});
    }
}

- (void)emitLocalSdp:(RTCSessionDescription *)sdp {
    if (self.onLocalSdpReady) {
        self.onLocalSdpReady(@{
            @"type": [self sdpTypeToString:sdp.type],
            @"sdp": sdp.sdp
        });
    }
}

- (void)emitRemoteStreamAdded:(NSString *)streamId {
    if (self.onRemoteStreamAdded) {
        self.onRemoteStreamAdded(@{@"streamId": streamId});
    }
}

- (void)emitConnectionError:(NSString *)error {
    if (self.onConnectionError) {
        self.onConnectionError(@{@"error": error});
    }
}

- (NSString *)sdpTypeToString:(RTCSdpType)type {
    switch (type) {
        case RTCSdpTypeOffer:
            return @"offer";
        case RTCSdpTypeAnswer:
            return @"answer";
        case RTCSdpTypePrAnswer:
            return @"pranswer";
        case RTCSdpTypeRollback:
            return @"rollback";
    }
}

- (void)dealloc {
    [self dispose];
}

@end
