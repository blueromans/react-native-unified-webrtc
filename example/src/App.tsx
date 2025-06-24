/* eslint-disable react-native/no-inline-styles */
import React, { useRef, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import {
  UnifiedWebrtcView,
  type UnifiedWebrtcViewRef,
} from 'react-native-unified-webrtc';

export default function App(): React.JSX.Element {
  const webrtcRef = useRef<UnifiedWebrtcViewRef>(null);
  const [streamUrl, setStreamUrl] = useState(
    'https://live.spacture.ai:8443/2/002104/whep' // H.264 codec (stable)
    // 'https://live.spacture.ai:8443/247/247102/whep' // H.265 codec (testing conditional support)
  );
  const [connectionStatus, setConnectionStatus] = useState<
    'disconnected' | 'connecting' | 'connected' | 'error' | 'disconnecting'
  >('disconnected');
  const [localSdp, setLocalSdp] = useState<{
    sdp: string;
    type: string;
  } | null>(null);
  const [remoteSdp, setRemoteSdp] = useState('');
  const [remoteSdpType, setRemoteSdpType] = useState<'offer' | 'answer'>(
    'offer'
  );
  const [iceCandidates, setIceCandidates] = useState<
    Array<{
      candidate: string;
      sdpMLineIndex: number;
      sdpMid: string;
    }>
  >([]);
  const [logs, setLogs] = useState<
    Array<{ message: string; timestamp: string }>
  >([]);
  const [showAdvancedControls, setShowAdvancedControls] = useState(false);

  const addLog = (message: string) => {
    const timestamp = new Date().toLocaleTimeString();
    setLogs((prev) => [{ message, timestamp }, ...prev.slice(0, 49)]);
  };

  const handleConnect = async () => {
    try {
      setConnectionStatus('connecting');
      addLog('Starting WebRTC connection...');
      addLog(`Stream URL: ${streamUrl}`);

      if (webrtcRef.current) {
        await webrtcRef.current.playStream(streamUrl);
        addLog('WebRTC stream initiated successfully');
        addLog('Waiting for signaling to complete...');
      }
    } catch (error) {
      addLog(`Connection failed: ${error}`);
      setConnectionStatus('error');
    }
  };

  const handleDisconnect = async () => {
    try {
      setConnectionStatus('disconnecting');
      addLog('WebRTC connection disposed');
      if (webrtcRef.current) {
        await webrtcRef.current.dispose();
      }
      setConnectionStatus('disconnected');
      setLocalSdp(null);
      setIceCandidates([]);
    } catch (error) {
      addLog(`Disconnect failed: ${error}`);
    }
  };

  const handleCreateOffer = async () => {
    try {
      addLog('Creating WebRTC offer...');
      await webrtcRef.current?.createOffer();
    } catch (error) {
      addLog(`Create offer failed: ${error}`);
    }
  };

  const handleCreateAnswer = async () => {
    try {
      addLog('Creating WebRTC answer...');
      await webrtcRef.current?.createAnswer();
    } catch (error) {
      addLog(`Create answer failed: ${error}`);
    }
  };

  const handleSetRemoteDescription = async () => {
    try {
      if (remoteSdp && remoteSdpType) {
        await webrtcRef.current?.setRemoteDescription(remoteSdp, remoteSdpType);
        addLog(`Set remote ${remoteSdpType} SDP`);
      }
    } catch (error) {
      addLog(`Set remote description failed: ${error}`);
    }
  };

  const handleLocalSdpReady = (event: {
    nativeEvent: { sdp: string; type: string };
  }) => {
    const { sdp, type } = event.nativeEvent;
    setLocalSdp({ sdp, type });
    addLog(`Local ${type} SDP ready (${sdp.length} chars)`);
    addLog(`SDP preview: ${sdp.substring(0, 100)}...`);
  };

  const handleIceCandidateReady = (event: {
    nativeEvent: { candidate: string; sdpMLineIndex: number; sdpMid: string };
  }) => {
    const { candidate, sdpMLineIndex, sdpMid } = event.nativeEvent;
    setIceCandidates((prev) => [...prev, { candidate, sdpMLineIndex, sdpMid }]);
    addLog(
      `ICE candidate ready: ${candidate.substring(0, 50)}... (line ${sdpMLineIndex})`
    );
  };

  const handleConnectionError = (event: { nativeEvent: { error: string } }) => {
    const { error } = event.nativeEvent;
    addLog(`Connection error: ${error}`);
    setConnectionStatus('error');
  };

  const handleConnectionStateChange = (event: {
    nativeEvent: { state: string; streamUrl: string };
  }) => {
    const { state, streamUrl: eventStreamUrl } = event.nativeEvent;
    addLog(`Connection state changed: ${state} for ${eventStreamUrl}`);

    switch (state) {
      case 'connected':
        setConnectionStatus('connected');
        break;
      case 'disconnected':
        setConnectionStatus('disconnected');
        break;
      case 'failed':
        setConnectionStatus('error');
        break;
      case 'closed':
        setConnectionStatus('disconnected');
        break;
      default:
        break;
    }
  };

  const clearLogs = () => {
    setLogs([]);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'disconnected':
        return styles.statusDisconnected;
      case 'connecting':
        return styles.statusConnecting;
      case 'connected':
        return styles.statusConnected;
      case 'error':
        return styles.statusError;
      case 'disconnecting':
        return styles.statusDisconnecting;
      default:
        return {};
    }
  };

  return (
    <View style={styles.container}>
      {/* WebRTC Video View */}
      <View style={styles.videoContainer}>
        <UnifiedWebrtcView
          ref={webrtcRef}
          style={styles.webrtcView}
          onLocalSdpReady={handleLocalSdpReady}
          onIceCandidateReady={handleIceCandidateReady}
          onConnectionError={handleConnectionError}
          onConnectionStateChange={handleConnectionStateChange}
        />
        <View style={styles.statusOverlay}>
          <Text style={[styles.statusText, { fontWeight: 'bold' }]}>
            Connection:{' '}
          </Text>
          <Text style={styles.statusText}>{connectionStatus}</Text>
        </View>
      </View>

      {/* Controls */}
      <View style={styles.controlsContainer}>
        <ScrollView style={styles.scrollContainer}>
          {/* Stream URL Input */}
          <View style={styles.inputGroup}>
            <Text style={styles.label}>Stream URL:</Text>
            <TextInput
              style={styles.textInput}
              value={streamUrl}
              onChangeText={setStreamUrl}
              placeholder="Enter WebRTC stream URL"
              multiline
            />
          </View>

          {/* Main Controls */}
          <View style={styles.buttonGroup}>
            <TouchableOpacity
              style={[
                styles.button,
                connectionStatus === 'connected' ||
                connectionStatus === 'connecting'
                  ? styles.buttonDisabled
                  : styles.buttonPrimary,
              ]}
              onPress={handleConnect}
              disabled={
                connectionStatus === 'connected' ||
                connectionStatus === 'connecting'
              }
            >
              <Text style={styles.buttonText}>Connect</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.button,
                connectionStatus === 'disconnected' ||
                connectionStatus === 'error' ||
                connectionStatus === 'disconnecting'
                  ? styles.buttonDisabled
                  : styles.buttonSecondary,
              ]}
              onPress={handleDisconnect}
              disabled={
                connectionStatus === 'disconnected' ||
                connectionStatus === 'error' ||
                connectionStatus === 'disconnecting'
              }
            >
              <Text style={styles.buttonText}>Disconnect</Text>
            </TouchableOpacity>
          </View>

          {/* Advanced Controls Toggle */}
          <TouchableOpacity
            style={[styles.button, styles.buttonTertiary]}
            onPress={() => setShowAdvancedControls(!showAdvancedControls)}
          >
            <Text style={styles.buttonText}>
              {showAdvancedControls ? 'Hide' : 'Show'} Advanced Controls
            </Text>
          </TouchableOpacity>

          {/* Advanced Controls */}
          {showAdvancedControls && (
            <View style={styles.advancedControls}>
              <Text style={styles.sectionTitle}>WebRTC Signaling</Text>

              <View style={styles.buttonGroup}>
                <TouchableOpacity
                  style={[styles.button, styles.buttonSecondary]}
                  onPress={handleCreateOffer}
                >
                  <Text style={styles.buttonText}>Create Offer</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={[styles.button, styles.buttonSecondary]}
                  onPress={handleCreateAnswer}
                >
                  <Text style={styles.buttonText}>Create Answer</Text>
                </TouchableOpacity>
              </View>

              {/* Local SDP Display */}
              {localSdp && (
                <View style={styles.inputGroup}>
                  <Text style={styles.label}>Local SDP:</Text>
                  <TextInput
                    style={[styles.textInput, styles.sdpInput]}
                    value={localSdp.sdp}
                    multiline
                    editable={false}
                  />
                </View>
              )}

              {/* Remote SDP Input */}
              <View style={styles.inputGroup}>
                <Text style={styles.label}>Remote SDP:</Text>
                <View style={styles.sdpTypeContainer}>
                  <TouchableOpacity
                    style={[
                      styles.sdpTypeButton,
                      remoteSdpType === 'offer' && styles.sdpTypeButtonActive,
                    ]}
                    onPress={() => setRemoteSdpType('offer')}
                  >
                    <Text style={styles.sdpTypeButtonText}>Offer</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[
                      styles.sdpTypeButton,
                      remoteSdpType === 'answer' && styles.sdpTypeButtonActive,
                    ]}
                    onPress={() => setRemoteSdpType('answer')}
                  >
                    <Text style={styles.sdpTypeButtonText}>Answer</Text>
                  </TouchableOpacity>
                </View>
                <TextInput
                  style={[styles.textInput, styles.sdpInput]}
                  value={remoteSdp}
                  onChangeText={setRemoteSdp}
                  placeholder="Paste remote SDP here"
                  multiline
                />
                <TouchableOpacity
                  style={[styles.button, styles.buttonSecondary]}
                  onPress={handleSetRemoteDescription}
                >
                  <Text style={styles.buttonText}>Set Remote SDP</Text>
                </TouchableOpacity>
              </View>

              {/* ICE Candidates Display */}
              {iceCandidates.length > 0 && (
                <View style={styles.inputGroup}>
                  <Text style={styles.label}>
                    ICE Candidates ({iceCandidates.length}):
                  </Text>
                  <ScrollView style={styles.iceCandidatesContainer}>
                    {iceCandidates.map((candidate, index) => (
                      <Text key={index} style={styles.iceCandidateText}>
                        {candidate.candidate.substring(0, 50)}... (line{' '}
                        {candidate.sdpMLineIndex})
                      </Text>
                    ))}
                  </ScrollView>
                </View>
              )}
            </View>
          )}

          {/* Debug Information */}
          <View style={styles.debugSection}>
            <Text style={styles.sectionTitle}>Debug Information</Text>
            <View style={styles.debugInfo}>
              <Text style={styles.debugLabel}>Connection Status:</Text>
              <Text
                style={[styles.debugValue, getStatusColor(connectionStatus)]}
              >
                {connectionStatus.toUpperCase()}
              </Text>
            </View>
            <View style={styles.debugInfo}>
              <Text style={styles.debugLabel}>Stream URL:</Text>
              <Text style={styles.debugValue} numberOfLines={2}>
                {streamUrl}
              </Text>
            </View>
            <View style={styles.debugInfo}>
              <Text style={styles.debugLabel}>Local SDP:</Text>
              <Text style={styles.debugValue}>
                {localSdp
                  ? `${localSdp.type} (${localSdp.sdp.length} chars)`
                  : 'Not generated'}
              </Text>
            </View>
            <View style={styles.debugInfo}>
              <Text style={styles.debugLabel}>ICE Candidates:</Text>
              <Text style={styles.debugValue}>
                {iceCandidates.length} candidates
              </Text>
            </View>
          </View>

          {/* Logs Section */}
          <View style={styles.logsSection}>
            <View style={styles.logHeader}>
              <Text style={styles.sectionTitle}>Connection Logs</Text>
              <TouchableOpacity
                style={[styles.button, styles.buttonSmall]}
                onPress={clearLogs}
              >
                <Text style={styles.buttonText}>Clear</Text>
              </TouchableOpacity>
            </View>
            <ScrollView style={styles.logsContainer}>
              {logs.map((log, index) => (
                <View key={index} style={styles.logEntry}>
                  <Text style={styles.logTimestamp}>{log.timestamp}</Text>
                  <Text style={styles.logMessage}>{log.message}</Text>
                </View>
              ))}
            </ScrollView>
          </View>
        </ScrollView>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  videoContainer: {
    flex: 1,
    position: 'relative',
    minHeight: 200,
  },
  webrtcView: {
    flex: 1,
    backgroundColor: '#222',
  },
  statusOverlay: {
    position: 'absolute',
    top: 10,
    left: 10,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
    flexDirection: 'row',
  },
  statusText: {
    color: '#fff',
    fontSize: 14,
  },
  controlsContainer: {
    backgroundColor: '#f5f5f5',
    maxHeight: 400,
  },
  scrollContainer: {
    padding: 16,
  },
  inputGroup: {
    marginBottom: 16,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#333',
  },
  textInput: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    fontSize: 14,
    backgroundColor: '#fff',
  },
  sdpInput: {
    height: 100,
    textAlignVertical: 'top',
  },
  buttonGroup: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 8,
    alignItems: 'center',
  },
  buttonPrimary: {
    backgroundColor: '#007AFF',
  },
  buttonSecondary: {
    backgroundColor: '#34C759',
  },
  buttonTertiary: {
    backgroundColor: '#FF9500',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonSmall: {
    flex: 0,
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  advancedControls: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 8,
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 12,
    color: '#333',
  },
  sdpTypeContainer: {
    flexDirection: 'row',
    marginBottom: 8,
  },
  sdpTypeButton: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 16,
    backgroundColor: '#e0e0e0',
    alignItems: 'center',
  },
  sdpTypeButtonActive: {
    backgroundColor: '#007AFF',
  },
  sdpTypeButtonText: {
    color: '#333',
    fontWeight: '600',
  },
  iceCandidatesContainer: {
    maxHeight: 100,
    backgroundColor: '#f9f9f9',
    padding: 8,
    borderRadius: 4,
  },
  iceCandidateText: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  logsSection: {
    marginTop: 16,
  },
  logHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  logsContainer: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    maxHeight: 200,
  },
  logEntry: {
    flexDirection: 'row',
    marginBottom: 4,
  },
  logTimestamp: {
    fontSize: 12,
    color: '#666',
    width: 80,
  },
  logMessage: {
    fontSize: 12,
    flex: 1,
  },
  debugSection: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 8,
    marginBottom: 16,
  },
  debugInfo: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  debugLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  debugValue: {
    fontSize: 14,
    color: '#666',
  },
  statusDisconnected: {
    color: '#666',
  },
  statusConnecting: {
    color: '#FF9500',
  },
  statusConnected: {
    color: '#34C759',
  },
  statusError: {
    color: '#FF0000',
  },
  statusDisconnecting: {
    color: '#FF9500',
  },
});
