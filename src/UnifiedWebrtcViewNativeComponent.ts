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

// Jitsi Meet specific event types
export type OnConferenceJoinedEventData = Readonly<{
  roomName: string;
  participantId: string;
  displayName: string;
}>;

export type OnConferenceLeftEventData = Readonly<{
  roomName: string;
  reason: string;
}>;

export type OnParticipantJoinedEventData = Readonly<{
  participantId: string;
  displayName: string;
  email?: string;
  avatarUrl?: string;
}>;

export type OnParticipantLeftEventData = Readonly<{
  participantId: string;
  displayName: string;
}>;

export type OnAudioMutedChangedEventData = Readonly<{
  participantId: string;
  muted: boolean;
}>;

export type OnVideoMutedChangedEventData = Readonly<{
  participantId: string;
  muted: boolean;
}>;

export type OnChatMessageReceivedEventData = Readonly<{
  senderId: string;
  senderDisplayName: string;
  message: string;
  timestamp: Double;
}>;

export type OnScreenShareToggledEventData = Readonly<{
  participantId: string;
  sharing: boolean;
}>;

export type OnConferenceErrorEventData = Readonly<{
  error: string;
  errorCode: string;
}>;

// Interface for props
export interface NativeProps extends ViewProps {
  color?: string;
  // WebRTC signaling callbacks
  onLocalSdpReady?: DirectEventHandler<OnLocalSdpEventData>;
  onIceCandidateReady?: DirectEventHandler<OnIceCandidateReadyEventData>;
  onConnectionError?: DirectEventHandler<OnConnectionErrorEventData>;
  onConnectionStateChange?: DirectEventHandler<OnConnectionStateChangeEventData>;

  // Jitsi Meet conference callbacks
  onConferenceJoined?: DirectEventHandler<OnConferenceJoinedEventData>;
  onConferenceLeft?: DirectEventHandler<OnConferenceLeftEventData>;
  onParticipantJoined?: DirectEventHandler<OnParticipantJoinedEventData>;
  onParticipantLeft?: DirectEventHandler<OnParticipantLeftEventData>;
  onAudioMutedChanged?: DirectEventHandler<OnAudioMutedChangedEventData>;
  onVideoMutedChanged?: DirectEventHandler<OnVideoMutedChangedEventData>;
  onChatMessageReceived?: DirectEventHandler<OnChatMessageReceivedEventData>;
  onScreenShareToggled?: DirectEventHandler<OnScreenShareToggledEventData>;
  onConferenceError?: DirectEventHandler<OnConferenceErrorEventData>;
}

// Interface for commands
interface NativeCommands {
  // Existing WebRTC commands
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

  // Jitsi Meet conference commands
  joinRoom: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    serverURL: string,
    roomName: string,
    jwt?: string,
    displayName?: string,
    email?: string,
    avatarUrl?: string
  ) => void;
  leaveRoom: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  toggleAudio: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  toggleVideo: (viewRef: React.ElementRef<HostComponent<NativeProps>>) => void;
  toggleScreenShare: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>
  ) => void;
  sendChatMessage: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    message: string
  ) => void;
  setDisplayName: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    displayName: string
  ) => void;
  setAudioMuted: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    muted: boolean
  ) => void;
  setVideoMuted: (
    viewRef: React.ElementRef<HostComponent<NativeProps>>,
    muted: boolean
  ) => void;
}

export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: [
    'playStream',
    'createOffer',
    'createAnswer',
    'setRemoteDescription',
    'addIceCandidate',
    'dispose',
    'joinRoom',
    'leaveRoom',
    'toggleAudio',
    'toggleVideo',
    'toggleScreenShare',
    'sendChatMessage',
    'setDisplayName',
    'setAudioMuted',
    'setVideoMuted',
  ],
});

export default codegenNativeComponent<NativeProps>(
  'UnifiedWebrtcView'
) as HostComponent<NativeProps>;
