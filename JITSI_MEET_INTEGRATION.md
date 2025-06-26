# Jitsi Meet Integration for React Native Unified WebRTC

This document describes the Jitsi Meet conference functionality integrated into the React Native Unified WebRTC plugin with support for the new React Native architecture (Fabric).

## Features

### Conference Management
- **Join/Leave Rooms**: Join and leave Jitsi Meet conference rooms
- **Room State Management**: Track conference connection state and participants
- **Display Name Management**: Set and update participant display names

### Media Controls
- **Audio Controls**: Mute/unmute audio for local participant
- **Video Controls**: Mute/unmute video for local participant
- **Screen Sharing**: Toggle screen sharing (iOS implementation pending)

### Participant Management
- **Participant Tracking**: Track participants joining and leaving
- **Participant Information**: Access participant display names, emails, and avatars
- **Real-time Updates**: Receive real-time updates on participant state changes

### Chat Support
- **Message Receiving**: Receive chat messages from other participants
- **Message Sending**: Send chat messages to the conference (implementation pending)
- **Message History**: Track chat message history with timestamps

### Event System
- **Real-time Events**: Comprehensive event system for conference state changes
- **Error Handling**: Proper error handling and reporting
- **State Synchronization**: Keep UI in sync with conference state

## iOS Implementation

### Dependencies
The iOS implementation uses the following dependencies:
- `JitsiMeetSDK` (~> 9.2.2) - Full Jitsi Meet conference functionality
- `JitsiWebRTC` - Low-level WebRTC functionality (existing)

### Architecture
- **JitsiMeetView Integration**: Embeds JitsiMeetView for conference UI
- **Delegate Pattern**: Uses JitsiMeetViewDelegate for event handling
- **State Management**: Tracks conference and participant state internally
- **Event Emission**: Forwards events to React Native using Fabric event system

### Key Components
1. **UnifiedWebrtcView.h**: Extended interface with Jitsi Meet properties and methods
2. **UnifiedWebrtcView.mm**: Full implementation with delegate methods and commands
3. **UnifiedWebrtcViewNativeComponent.ts**: TypeScript interface for Fabric integration

## Usage Example

```tsx
import React, { useRef, useState } from 'react';
import { View, TouchableOpacity, Text } from 'react-native';
import UnifiedWebrtcView from 'react-native-unified-webrtc';

const ConferenceComponent = () => {
  const webrtcRef = useRef(null);
  const [isInConference, setIsInConference] = useState(false);

  const joinRoom = () => {
    webrtcRef.current?.joinRoom('my-room-123', 'John Doe');
  };

  const leaveRoom = () => {
    webrtcRef.current?.leaveRoom();
  };

  const toggleAudio = () => {
    webrtcRef.current?.toggleAudio();
  };

  const handleConferenceJoined = (event) => {
    console.log('Joined room:', event.nativeEvent.roomName);
    setIsInConference(true);
  };

  const handleConferenceLeft = (event) => {
    console.log('Left room:', event.nativeEvent.roomName);
    setIsInConference(false);
  };

  const handleParticipantJoined = (event) => {
    console.log('Participant joined:', event.nativeEvent.displayName);
  };

  return (
    <View style={{ flex: 1 }}>
      <UnifiedWebrtcView
        ref={webrtcRef}
        style={{ flex: 1 }}
        onConferenceJoined={handleConferenceJoined}
        onConferenceLeft={handleConferenceLeft}
        onParticipantJoined={handleParticipantJoined}
        onParticipantLeft={handleParticipantLeft}
        onAudioMutedChanged={handleAudioMutedChanged}
        onVideoMutedChanged={handleVideoMutedChanged}
        onChatMessageReceived={handleChatMessageReceived}
        onConferenceError={handleConferenceError}
      />
      
      <View style={{ flexDirection: 'row', padding: 16 }}>
        {!isInConference ? (
          <TouchableOpacity onPress={joinRoom}>
            <Text>Join Room</Text>
          </TouchableOpacity>
        ) : (
          <>
            <TouchableOpacity onPress={leaveRoom}>
              <Text>Leave Room</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={toggleAudio}>
              <Text>Toggle Audio</Text>
            </TouchableOpacity>
          </>
        )}
      </View>
    </View>
  );
};
```

## API Reference

### Commands

#### `joinRoom(roomName: string, displayName?: string)`
Join a Jitsi Meet conference room.
- `roomName`: The name of the room to join
- `displayName`: Optional display name for the participant

#### `leaveRoom()`
Leave the current conference room.

#### `toggleAudio()`
Toggle audio mute state for the local participant.

#### `toggleVideo()`
Toggle video mute state for the local participant.

#### `toggleScreenShare()`
Toggle screen sharing for the local participant.

#### `sendChatMessage(message: string)`
Send a chat message to the conference.

#### `setDisplayName(displayName: string)`
Update the display name for the local participant.

#### `setAudioMuted(muted: boolean)`
Set the audio mute state explicitly.

#### `setVideoMuted(muted: boolean)`
Set the video mute state explicitly.

### Events

#### `onConferenceJoined`
Fired when successfully joined a conference.
```tsx
onConferenceJoined={(event) => {
  const { roomName, participantId, displayName } = event.nativeEvent;
}}
```

#### `onConferenceLeft`
Fired when left a conference.
```tsx
onConferenceLeft={(event) => {
  const { roomName, reason } = event.nativeEvent;
}}
```

#### `onParticipantJoined`
Fired when a participant joins the conference.
```tsx
onParticipantJoined={(event) => {
  const { participantId, displayName, email, avatarUrl } = event.nativeEvent;
}}
```

#### `onParticipantLeft`
Fired when a participant leaves the conference.
```tsx
onParticipantLeft={(event) => {
  const { participantId, displayName } = event.nativeEvent;
}}
```

#### `onAudioMutedChanged`
Fired when a participant's audio mute state changes.
```tsx
onAudioMutedChanged={(event) => {
  const { participantId, muted } = event.nativeEvent;
}}
```

#### `onVideoMutedChanged`
Fired when a participant's video mute state changes.
```tsx
onVideoMutedChanged={(event) => {
  const { participantId, muted } = event.nativeEvent;
}}
```

#### `onChatMessageReceived`
Fired when a chat message is received.
```tsx
onChatMessageReceived={(event) => {
  const { senderId, senderDisplayName, message, timestamp } = event.nativeEvent;
}}
```

#### `onScreenShareToggled`
Fired when screen sharing is toggled.
```tsx
onScreenShareToggled={(event) => {
  const { participantId, sharing } = event.nativeEvent;
}}
```

#### `onConferenceError`
Fired when a conference error occurs.
```tsx
onConferenceError={(event) => {
  const { error, errorCode } = event.nativeEvent;
}}
```

## Implementation Status

### ✅ Completed
- [x] Basic conference join/leave functionality
- [x] Audio/video mute controls
- [x] Participant management and events
- [x] Chat message receiving
- [x] Event system and error handling
- [x] TypeScript interface definitions
- [x] iOS native implementation
- [x] Fabric integration
- [x] Example test component

### 🚧 In Progress / TODO
- [ ] Screen sharing implementation (iOS permissions and APIs)
- [ ] Chat message sending (SDK limitations)
- [ ] Advanced participant features (reactions, hand raising)
- [ ] Conference recording controls
- [ ] Custom conference server configuration
- [ ] Android implementation (if needed)
- [ ] Unit and integration tests
- [ ] Performance optimization
- [ ] Memory management improvements

### 🔧 Technical Notes

#### iOS Specific
- Uses `JitsiMeetView` for conference UI rendering
- Implements `JitsiMeetViewDelegate` for event handling
- Manages view hierarchy with proper layout constraints
- Handles cleanup and memory management in dispose method

#### React Native Fabric
- Uses Fabric codegen for type-safe native interface
- Implements direct event handlers for real-time events
- Supports command dispatching for conference controls
- Maintains backward compatibility with existing WebRTC features

#### State Management
- Tracks conference state internally in native code
- Synchronizes participant information across events
- Maintains mute states for local participant
- Provides clean state reset on conference leave

## Testing

A comprehensive test component is available at `example/JitsiMeetTest.tsx` that demonstrates:
- Conference room joining and leaving
- Media controls (audio/video muting)
- Participant list management
- Chat message display
- Real-time event handling
- Error handling and user feedback

## Compatibility

This implementation maintains full backward compatibility with existing WebRTC streaming and WHEP protocol features while adding comprehensive Jitsi Meet conference functionality.

## Support

For issues, feature requests, or questions about the Jitsi Meet integration, please refer to the main project documentation or create an issue in the project repository.
