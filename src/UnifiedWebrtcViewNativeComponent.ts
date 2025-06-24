import * as React from 'react';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';
import codegenNativeCommands from 'react-native/Libraries/Utilities/codegenNativeCommands';
import type { HostComponent, ViewProps } from 'react-native';
import type {
  DirectEventHandler,
  Double,
} from 'react-native/Libraries/Types/CodegenTypes';

// Event types for signaling
export type OnLocalSdpEventData = Readonly<{
  sdp: string;
  type: string;
}>;

export type OnIceCandidateReadyEventData = Readonly<{
  candidate: string;
  sdpMLineIndex: Double;
  sdpMid: string;
}>;

export type OnConnectionErrorEventData = Readonly<{
  error: string;
  streamUrl: string;
}>;

export type OnConnectionStateChangeEventData = Readonly<{
  state: string;
  streamUrl: string;
}>;

// Interface for props
export interface NativeProps extends ViewProps {
  color?: string;
  // Callbacks for WebRTC signaling
  onLocalSdpReady?: DirectEventHandler<OnLocalSdpEventData>;
  onIceCandidateReady?: DirectEventHandler<OnIceCandidateReadyEventData>;
  onConnectionError?: DirectEventHandler<OnConnectionErrorEventData>;
  onConnectionStateChange?: DirectEventHandler<OnConnectionStateChangeEventData>;
}

// Interface for commands
interface NativeCommands {
  playStream: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    streamUrlOrSignalingInfo: string
  ) => void;
  createOffer: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  createAnswer: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  setRemoteDescription: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    sdp: string,
    type: string
  ) => void;
  addIceCandidate: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    candidateSdp: string,
    sdpMLineIndex: Double,
    sdpMid: string
  ) => void;
  dispose: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
}

export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: [
    'playStream',
    'createOffer',
    'createAnswer',
    'setRemoteDescription',
    'addIceCandidate',
    'dispose',
  ],
});

export default codegenNativeComponent<NativeProps>(
  'UnifiedWebrtcView'
) as HostComponent<NativeProps>;
