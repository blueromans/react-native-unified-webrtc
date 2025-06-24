import * as React from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import UnifiedWebrtcViewNativeComponent, {
  Commands,
  type OnLocalSdpEventData,
  type OnIceCandidateReadyEventData,
  type OnConnectionErrorEventData,
  type OnConnectionStateChangeEventData,
} from './UnifiedWebrtcViewNativeComponent';

export interface UnifiedWebrtcViewProps extends ViewProps {
  color?: string;
  onLocalSdpReady?: (event: {
    nativeEvent: { sdp: string; type: string };
  }) => void;
  onIceCandidateReady?: (event: {
    nativeEvent: { candidate: string; sdpMLineIndex: number; sdpMid: string };
  }) => void;
  onConnectionError?: (event: {
    nativeEvent: { error: string; streamUrl: string };
  }) => void;
  onConnectionStateChange?: (event: {
    nativeEvent: { state: string; streamUrl: string };
  }) => void;
}

// Interface for the imperative commands exposed by the component's ref
export interface UnifiedWebrtcViewRef {
  playStream: (streamUrlOrSignalingInfo: string) => void;
  createOffer: () => void;
  createAnswer: () => void;
  setRemoteDescription: (sdp: string, type: string) => void;
  addIceCandidate: (
    candidateSdp: string,
    sdpMLineIndex: number,
    sdpMid: string
  ) => void;
  dispose: () => void;
}

export const UnifiedWebrtcView = React.forwardRef<
  UnifiedWebrtcViewRef,
  UnifiedWebrtcViewProps
>((props, ref) => {
  const nativeRef =
    React.useRef<React.ElementRef<typeof UnifiedWebrtcViewNativeComponent>>(
      null
    );

  React.useImperativeHandle(ref, () => ({
    playStream: (streamUrlOrSignalingInfo: string) => {
      if (nativeRef.current) {
        Commands.playStream(nativeRef.current, streamUrlOrSignalingInfo);
      }
    },
    createOffer: () => {
      if (nativeRef.current) {
        Commands.createOffer(nativeRef.current);
      }
    },
    createAnswer: () => {
      if (nativeRef.current) {
        Commands.createAnswer(nativeRef.current);
      }
    },
    setRemoteDescription: (sdp: string, type: string) => {
      if (nativeRef.current) {
        Commands.setRemoteDescription(nativeRef.current, sdp, type);
      }
    },
    addIceCandidate: (
      candidateSdp: string,
      sdpMLineIndex: number,
      sdpMid: string
    ) => {
      if (nativeRef.current) {
        Commands.addIceCandidate(
          nativeRef.current,
          candidateSdp,
          sdpMLineIndex,
          sdpMid
        );
      }
    },
    dispose: () => {
      if (nativeRef.current) {
        Commands.dispose(nativeRef.current);
      }
    },
  }));

  const handleLocalSdpReady = (
    event: NativeSyntheticEvent<OnLocalSdpEventData>
  ) => {
    props.onLocalSdpReady?.(event);
  };

  const handleIceCandidateReady = (
    event: NativeSyntheticEvent<OnIceCandidateReadyEventData>
  ) => {
    props.onIceCandidateReady?.(event);
  };

  const handleConnectionError = (
    event: NativeSyntheticEvent<OnConnectionErrorEventData>
  ) => {
    props.onConnectionError?.(event);
  };

  const handleConnectionStateChange = (
    event: NativeSyntheticEvent<OnConnectionStateChangeEventData>
  ) => {
    props.onConnectionStateChange?.(event);
  };

  return (
    <UnifiedWebrtcViewNativeComponent
      color={props.color}
      style={props.style}
      ref={nativeRef}
      onLocalSdpReady={handleLocalSdpReady}
      onIceCandidateReady={handleIceCandidateReady}
      onConnectionError={handleConnectionError}
      onConnectionStateChange={handleConnectionStateChange}
    />
  );
});

UnifiedWebrtcView.displayName = 'UnifiedWebrtcView';

export default UnifiedWebrtcView;
