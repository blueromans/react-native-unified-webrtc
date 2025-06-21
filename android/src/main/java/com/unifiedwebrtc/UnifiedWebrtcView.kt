package com.unifiedwebrtc

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.FrameLayout
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.events.RCTEventEmitter
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.webrtc.*
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import java.net.URI

class UnifiedWebrtcView(context: Context) : FrameLayout(context) {

    private val TAG = "UnifiedWebrtcView"
    private val eglBaseContext: EglBase.Context = EglBase.create().eglBaseContext
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var localVideoTrack: VideoTrack? = null
    private var remoteVideoTrack: VideoTrack? = null
    private var surfaceViewRenderer: SurfaceViewRenderer? = null
    private var peerConnection: PeerConnection? = null
    private var reactContext: ThemedReactContext? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var iceGatheringComplete = false
    private var pendingStreamUrl: String? = null
    private var localOffer: SessionDescription? = null

    init {
        if (context is ThemedReactContext) {
            reactContext = context
            initializeWebRTC(context)
        }
    }

    private fun initializeWebRTC(reactContext: ThemedReactContext) {
        Log.d(TAG, "Initializing WebRTC")
        
        // Initialize PeerConnectionFactory with H.265 support
        val options = PeerConnectionFactory.InitializationOptions.builder(reactContext.applicationContext)
            .setEnableInternalTracer(true)
            .setFieldTrials("WebRTC-H264HighProfile/Enabled/WebRTC-H265/Enabled/")
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)

        // Create video decoder/encoder factories with H.265 support
        val videoDecoderFactory = DefaultVideoDecoderFactory(eglBaseContext)
        val videoEncoderFactory = DefaultVideoEncoderFactory(eglBaseContext, true, true)

        val factoryBuilder = PeerConnectionFactory.builder()
            .setVideoDecoderFactory(videoDecoderFactory)
            .setVideoEncoderFactory(videoEncoderFactory)
            .setOptions(PeerConnectionFactory.Options())

        peerConnectionFactory = factoryBuilder.createPeerConnectionFactory()

        // Create SurfaceViewRenderer for video
        surfaceViewRenderer = SurfaceViewRenderer(context)
        surfaceViewRenderer?.init(eglBaseContext, null)
        surfaceViewRenderer?.setMirror(false)
        surfaceViewRenderer?.setEnableHardwareScaler(true)
        surfaceViewRenderer?.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
        
        val layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        addView(surfaceViewRenderer, layoutParams)
        
        Log.d(TAG, "WebRTC initialization complete")
    }

    private fun getIceServers(): List<PeerConnection.IceServer> {
        return listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun2.l.google.com:19302").createIceServer()
        )
    }

    private fun sendEventToReactNative(eventName: String, params: WritableMap) {
        reactContext?.getJSModule(RCTEventEmitter::class.java)?.receiveEvent(
            id,
            eventName,
            params
        )
    }

    fun createOffer() {
        Log.d(TAG, "Creating WebRTC offer")
        
        if (peerConnection == null) {
            setupPeerConnection()
        }

        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "false"))
        }

        peerConnection?.createOffer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                Log.d(TAG, "Offer created successfully")
                sdp?.let {
                    peerConnection?.setLocalDescription(SdpObserverAdapter(), it)
                    
                    // Send SDP to React Native
                    val params = Arguments.createMap().apply {
                        putString("type", it.type.canonicalForm())
                        putString("sdp", it.description)
                    }
                    sendEventToReactNative("onLocalSdpReady", params)
                }
            }

            override fun onCreateFailure(error: String?) {
                Log.e(TAG, "Failed to create offer: $error")
            }
        }, constraints)
    }

    fun createAnswer() {
        Log.d(TAG, "Creating WebRTC answer")
        
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
        }

        peerConnection?.createAnswer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                Log.d(TAG, "Answer created successfully")
                sdp?.let {
                    peerConnection?.setLocalDescription(SdpObserverAdapter(), it)
                    
                    // Send SDP to React Native
                    val params = Arguments.createMap().apply {
                        putString("type", it.type.canonicalForm())
                        putString("sdp", it.description)
                    }
                    sendEventToReactNative("onLocalSdpReady", params)
                }
            }

            override fun onCreateFailure(error: String?) {
                Log.e(TAG, "Failed to create answer: $error")
            }
        }, constraints)
    }

    fun setRemoteDescription(sdp: SessionDescription) {
        Log.d(TAG, "Setting remote description: ${sdp.type}")
        peerConnection?.setRemoteDescription(object : SdpObserverAdapter() {
            override fun onSetSuccess() {
                Log.d(TAG, "Remote description set successfully")
            }

            override fun onSetFailure(error: String?) {
                Log.e(TAG, "Failed to set remote description: $error")
            }
        }, sdp)
    }

    fun addIceCandidate(candidate: IceCandidate) {
        Log.d(TAG, "Adding ICE candidate: ${candidate.sdpMid}")
        peerConnection?.addIceCandidate(candidate)
    }

    fun playStream(streamUrlOrSignalingInfo: String) {
        Log.d(TAG, "Starting stream playback: $streamUrlOrSignalingInfo")
        
        executor.execute {
            try {
                if (peerConnection == null) {
                    setupPeerConnection()
                }
                
                // For WebRTC streaming URLs, we need to:
                // 1. Create an offer
                // 2. Send it to the streaming server's signaling endpoint
                // 3. Receive the answer and set it as remote description
                
                // First, create an offer
                createOffer()
                
                // For now, we'll create the offer and let the React Native layer
                // handle the signaling. In a real implementation, you would:
                // - Parse the streaming URL to extract signaling endpoint
                // - Send HTTP POST with the offer to the signaling server
                // - Receive the answer and set it as remote description
                // - Handle ICE candidate exchange
                
                Log.d(TAG, "WebRTC offer creation initiated for stream: $streamUrlOrSignalingInfo")
                
                // Attempt WebRTC signaling with the streaming server
                attemptSignaling(streamUrlOrSignalingInfo)
                
            } catch (e: Exception) {
                Log.e(TAG, "Error starting stream: ${e.message}")
                // Emit error event to React Native
                val params = Arguments.createMap().apply {
                    putString("error", e.message ?: "Unknown error")
                    putString("streamUrl", streamUrlOrSignalingInfo)
                }
                (context as? ThemedReactContext)?.getJSModule(RCTEventEmitter::class.java)?.receiveEvent(id, "onConnectionError", params)
            }
        }
    }

    private fun attemptSignaling(streamUrlOrSignalingInfo: String) {
        Log.d(TAG, "Starting signaling for: $streamUrlOrSignalingInfo")
        
        // Check if this is a direct WHEP URL (like the working web example)
        if (streamUrlOrSignalingInfo.contains("/whep")) {
            Log.d(TAG, "=== DIRECT WHEP URL DETECTED ===")
            pendingStreamUrl = streamUrlOrSignalingInfo
            
            // Create offer and wait for ICE gathering completion
            peerConnection?.createOffer(object : SdpObserver {
                override fun onCreateSuccess(offer: SessionDescription?) {
                    offer?.let {
                        Log.d(TAG, "Local offer created, setting as local description...")
                        peerConnection?.setLocalDescription(object : SdpObserver {
                            override fun onSetSuccess() {
                                Log.d(TAG, "Local description set. Waiting for ICE gathering...")
                                // Emit the local SDP to React Native
                                emitLocalSdp(it)
                                
                                // If ICE gathering is already complete, send immediately
                                if (iceGatheringComplete) {
                                    sendWhepOffer(streamUrlOrSignalingInfo)
                                }
                                // Otherwise wait for onIceGatheringChange callback
                            }
                            override fun onSetFailure(error: String?) {
                                Log.e(TAG, "Failed to set local description: $error")
                                emitConnectionError("Failed to set local description: $error")
                            }
                            override fun onCreateSuccess(p0: SessionDescription?) {}
                            override fun onCreateFailure(p0: String?) {}
                        }, it)
                    }
                }
                override fun onCreateFailure(error: String?) {
                    Log.e(TAG, "Failed to create offer: $error")
                    emitConnectionError("Failed to create offer: $error")
                }
                override fun onSetSuccess() {}
                override fun onSetFailure(p0: String?) {}
            }, MediaConstraints())
            return
        }
        
        // For non-WHEP URLs, try alternative signaling methods
        val streamId = extractStreamId(streamUrlOrSignalingInfo)
        
        // Wait for local SDP offer to be ready
        if (localOffer == null) {
            Log.d(TAG, "Creating local offer first...")
            peerConnection?.createOffer(object : SdpObserver {
                override fun onCreateSuccess(offer: SessionDescription?) {
                    offer?.let {
                        localOffer = it
                        peerConnection?.setLocalDescription(SdpObserverAdapter(), it)
                        emitLocalSdp(it)
                        // Retry signaling with the offer
                        tryAlternativeSignaling(streamUrlOrSignalingInfo, streamId, it)
                    }
                }
                override fun onCreateFailure(error: String?) {
                    Log.e(TAG, "Failed to create offer: $error")
                    emitConnectionError("Failed to create offer: $error")
                }
                override fun onSetSuccess() {}
                override fun onSetFailure(p0: String?) {}
            }, MediaConstraints())
        } else {
            tryAlternativeSignaling(streamUrlOrSignalingInfo, streamId, localOffer!!)
        }
    }
    
    private fun extractStreamId(streamUrl: String): String {
        return try {
            // Extract stream ID from URL like: https://live.spacture.ai:8443/248/holiday-farms-1-park-plaza_9090_cam_02
            val uri = URI(streamUrl)
            val path = uri.path.trimStart('/')
            Log.d(TAG, "Extracted path: $path")
            path // Return the full path as stream ID
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting stream ID: ${e.message}")
            ""
        }
    }
    
    private fun emitConnectionError(message: String) {
        val params = Arguments.createMap().apply {
            putString("error", message)
        }
        (context as? ThemedReactContext)?.getJSModule(RCTEventEmitter::class.java)?.receiveEvent(id, "onConnectionError", params)
    }
    
    private fun tryDirectConnection(streamUrl: String, streamId: String, offer: SessionDescription): Boolean {
        Log.d(TAG, "Attempting direct connection test...")
        
        // For testing: create a dummy answer SDP to see if the connection flow works
        val dummyAnswer = """v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
a=msid-semantic: WMS
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:test
a=ice-pwd:testpassword
a=ice-options:trickle
a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
a=setup:active
a=mid:0
a=sendonly
a=rtcp-mux
a=rtcp-rsize
a=rtpmap:96 H264/90000
a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f"""
        
        try {
            Log.d(TAG, "Setting dummy answer SDP for testing...")
            val answerSdp = SessionDescription(SessionDescription.Type.ANSWER, dummyAnswer)
            
            peerConnection?.setRemoteDescription(object : SdpObserver {
                override fun onCreateSuccess(p0: SessionDescription?) {}
                override fun onSetSuccess() {
                    Log.d(TAG, "Direct connection test: Remote description set successfully")
                    // This is just a test - in reality we need proper signaling
                }
                override fun onCreateFailure(p0: String?) {
                    Log.e(TAG, "Direct connection test: Create failure: $p0")
                }
                override fun onSetFailure(p0: String?) {
                    Log.e(TAG, "Direct connection test: Set remote description failed: $p0")
                }
            }, answerSdp)
            
            // Return false since this is just a test
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "Direct connection test failed: ${e.message}")
            return false
        }
    }
    
    private fun tryWebSocketSignaling(streamUrlOrSignalingInfo: String, streamId: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Attempting WebSocket signaling for stream: $streamId")
            
            val baseUrl = extractBaseUrl(streamUrlOrSignalingInfo)
            
            // SpactureAI specific WebSocket endpoints to try
            val wsEndpoints = listOf(
                "$baseUrl/ws",
                "$baseUrl/websocket", 
                "$baseUrl/signaling",
                "$baseUrl/webrtc/ws",
                "$baseUrl/$streamId/ws",
                "$baseUrl/stream/$streamId/ws"
            )
            
            // Try each WebSocket endpoint with real connections
            for (wsUrl in wsEndpoints) {
                Log.d(TAG, "Trying WebSocket endpoint: ${wsUrl.replace("https://", "wss://")}")
                if (tryRealWebSocketConnection(wsUrl.replace("https://", "wss://"), streamId, offer)) {
                    Log.d(TAG, "WebSocket signaling successful!")
                    return true
                }
            }
            
            // If WebSocket fails, try alternative signaling approaches
            Log.d(TAG, "WebSocket signaling failed, trying alternative approaches...")
            return tryAlternativeSignaling(streamUrlOrSignalingInfo, streamId, offer)
            
        } catch (e: Exception) {
            Log.e(TAG, "WebSocket signaling error: ${e.message}")
            false
        }
    }
    
    private fun tryRealWebSocketConnection(wsUrl: String, streamId: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Attempting real WebSocket connection to: $wsUrl")
            
            val client = OkHttpClient.Builder()
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(10, TimeUnit.SECONDS)
                .build()
            
            val request = Request.Builder()
                .url(wsUrl)
                .build()
            
            var connectionSuccessful = false
            val latch = CountDownLatch(1)
            
            val webSocket = client.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Log.d(TAG, "WebSocket connected to: $wsUrl")
                    
                    // Try different SpactureAI signaling message formats
                    val messages = listOf(
                        // Standard WebRTC signaling
                        """{"type":"offer","sdp":"${offer.description}","streamId":"$streamId"}""",
                        
                        // SpactureAI specific formats (guessing based on common patterns)
                        """{"action":"play","streamId":"$streamId","offer":{"type":"offer","sdp":"${offer.description}"}}""",
                        """{"cmd":"start","stream":"$streamId","sdp":{"type":"offer","sdp":"${offer.description}"}}""",
                        """{"method":"play","params":{"streamId":"$streamId","offer":"${offer.description}"}}""",
                        
                        // Simple formats
                        """{"play":"$streamId","offer":"${offer.description}"}""",
                        """{"stream":"$streamId","type":"offer","sdp":"${offer.description}"}"""
                    )
                    
                    // Send the first message format
                    webSocket.send(messages[0])
                    Log.d(TAG, "Sent WebSocket message: ${messages[0].take(100)}...")
                }
                
                override fun onMessage(webSocket: WebSocket, text: String) {
                    Log.d(TAG, "WebSocket message received: $text")
                    
                    try {
                        // Try to parse as JSON and look for answer SDP
                        val jsonResponse = org.json.JSONObject(text)
                        
                        // Check for answer SDP in various formats
                        val answerSdp = when {
                            jsonResponse.has("answer") -> {
                                val answer = jsonResponse.getJSONObject("answer")
                                if (answer.has("sdp")) answer.getString("sdp") else null
                            }
                            jsonResponse.has("sdp") && jsonResponse.getString("type") == "answer" -> {
                                jsonResponse.getString("sdp")
                            }
                            jsonResponse.has("result") -> {
                                val result = jsonResponse.getJSONObject("result")
                                if (result.has("sdp")) result.getString("sdp") else null
                            }
                            else -> null
                        }
                        
                        if (answerSdp != null) {
                            Log.d(TAG, "Received answer SDP: ${answerSdp.take(100)}...")
                            
                            // Set remote description
                            val remoteSdp = SessionDescription(SessionDescription.Type.ANSWER, answerSdp)
                            peerConnection?.setRemoteDescription(object : SdpObserver {
                                override fun onCreateSuccess(p0: SessionDescription?) {}
                                override fun onSetSuccess() {
                                    Log.d(TAG, "Remote description set successfully via WebSocket!")
                                    connectionSuccessful = true
                                    latch.countDown()
                                }
                                override fun onCreateFailure(p0: String?) {
                                    Log.e(TAG, "Create failure: $p0")
                                    latch.countDown()
                                }
                                override fun onSetFailure(p0: String?) {
                                    Log.e(TAG, "Set remote description failed: $p0")
                                    latch.countDown()
                                }
                            }, remoteSdp)
                        } else {
                            Log.d(TAG, "No answer SDP found in response, trying next message format...")
                        }
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "Error parsing WebSocket response: ${e.message}")
                        latch.countDown()
                    }
                }
                
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.e(TAG, "WebSocket connection failed: ${t.message}")
                    latch.countDown()
                }
                
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    Log.d(TAG, "WebSocket closed: $code - $reason")
                    latch.countDown()
                }
            })
            
            // Wait for connection result
            latch.await(10, TimeUnit.SECONDS)
            webSocket.close(1000, "Done")
            
            connectionSuccessful
            
        } catch (e: Exception) {
            Log.e(TAG, "Real WebSocket connection failed: ${e.message}")
            false
        }
    }
    
    private fun tryAlternativeSignaling(streamUrl: String, streamId: String, offer: SessionDescription): Boolean {
        Log.d(TAG, "Trying alternative signaling approaches...")
        
        // First, try to discover what SpactureAI actually serves
        if (discoverStreamingProtocol(streamUrl)) {
            return true
        }
        
        // Try WHIP signaling
        Log.d(TAG, "Trying WHIP signaling...")
        if (tryWhipSignaling(streamUrl, offer)) {
            return true
        }
        
        // Try WHEP signaling
        Log.d(TAG, "Trying WHEP signaling...")
        if (tryWhepSignaling(streamUrl, offer)) {
            return true
        }
        
        // Try direct SDP exchange
        Log.d(TAG, "Trying direct SDP exchange...")
        if (tryDirectSdpExchange(streamUrl, streamId, offer)) {
            return true
        }
        
        // Try streaming service specific endpoints
        Log.d(TAG, "Trying streaming service specific endpoints...")
        if (tryStreamingServiceEndpoints(streamUrl, streamId, offer)) {
            return true
        }
        
        // Last resort: Try HLS/DASH protocols
        Log.d(TAG, "Trying HLS/DASH fallback...")
        return tryHlsDashFallback(streamUrl, streamId)
    }
    
    private fun discoverStreamingProtocol(streamUrl: String): Boolean {
        return try {
            Log.d(TAG, "=== DISCOVERING SPACTURE AI STREAMING PROTOCOL ===")
            
            val baseUrl = streamUrl.substringBefore("/248")
            val streamPath = streamUrl.substringAfter(baseUrl)
            
            // Try common streaming manifest endpoints
            val manifestEndpoints = listOf(
                "$streamUrl.m3u8",           // HLS manifest
                "$streamUrl/playlist.m3u8",  // HLS playlist
                "$streamUrl.mpd",            // DASH manifest
                "$streamUrl/manifest.mpd",   // DASH manifest
                "$baseUrl/hls$streamPath.m3u8",     // HLS in hls directory
                "$baseUrl/dash$streamPath.mpd",     // DASH in dash directory
                "$baseUrl/stream$streamPath.m3u8",  // HLS in stream directory
                "$baseUrl/live$streamPath.m3u8"     // HLS in live directory
            )
            
            for (endpoint in manifestEndpoints) {
                Log.d(TAG, "Checking manifest endpoint: $endpoint")
                if (checkEndpointExists(endpoint)) {
                    Log.d(TAG, "Found streaming manifest at: $endpoint")
                    emitConnectionError("SpactureAI uses ${getProtocolType(endpoint)} streaming, not WebRTC. Manifest found at: $endpoint")
                    return true
                }
            }
            
            // Try to discover API endpoints by checking common paths
            val apiEndpoints = listOf(
                "$baseUrl/api/streams",
                "$baseUrl/api/live",
                "$baseUrl/api/channels",
                "$baseUrl/streams",
                "$baseUrl/channels",
                "$baseUrl/live"
            )
            
            for (endpoint in apiEndpoints) {
                Log.d(TAG, "Checking API endpoint: $endpoint")
                val response = checkEndpointWithDetails(endpoint)
                if (response.isNotEmpty() && !response.contains("404")) {
                    Log.d(TAG, "Found API endpoint: $endpoint - Response: ${response.take(200)}")
                    emitConnectionError("Found SpactureAI API at: $endpoint. Response: ${response.take(100)}...")
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.e(TAG, "Protocol discovery failed: ${e.message}")
            false
        }
    }
    
    private fun getProtocolType(url: String): String {
        return when {
            url.contains(".m3u8") -> "HLS"
            url.contains(".mpd") -> "DASH"
            else -> "Unknown"
        }
    }
    
    private fun checkEndpointExists(endpoint: String): Boolean {
        return try {
            val url = URL(endpoint)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "HEAD"
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            
            val responseCode = connection.responseCode
            Log.d(TAG, "Endpoint $endpoint returned: $responseCode")
            
            responseCode == 200
        } catch (e: Exception) {
            Log.d(TAG, "Endpoint check failed for $endpoint: ${e.message}")
            false
        }
    }
    
    private fun checkEndpointWithDetails(endpoint: String): String {
        return try {
            val url = URL(endpoint)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            
            val responseCode = connection.responseCode
            Log.d(TAG, "API endpoint $endpoint returned: $responseCode")
            
            if (responseCode == 200) {
                val reader = BufferedReader(InputStreamReader(connection.inputStream))
                val response = reader.readText()
                reader.close()
                response
            } else {
                "HTTP $responseCode"
            }
        } catch (e: Exception) {
            Log.d(TAG, "API endpoint check failed for $endpoint: ${e.message}")
            ""
        }
    }
    
    private fun tryHlsDashFallback(streamUrl: String, streamId: String): Boolean {
        Log.d(TAG, "=== TRYING HLS/DASH FALLBACK ===")
        
        // SpactureAI might be serving HLS or DASH instead of WebRTC
        val baseUrl = streamUrl.substringBefore("/248")
        val streamPath = streamUrl.substringAfter(baseUrl)
        
        val streamingUrls = listOf(
            "$streamUrl.m3u8",
            "$streamUrl/index.m3u8",
            "$baseUrl/hls$streamPath.m3u8",
            "$baseUrl/stream$streamPath.m3u8"
        )
        
        for (hlsUrl in streamingUrls) {
            Log.d(TAG, "Trying HLS URL: $hlsUrl")
            if (checkEndpointExists(hlsUrl)) {
                Log.d(TAG, "Found HLS stream at: $hlsUrl")
                emitConnectionError("SpactureAI serves HLS streams, not WebRTC. Use HLS player for: $hlsUrl")
                return true
            }
        }
        
        emitConnectionError("SpactureAI uses proprietary signaling. All standard WebRTC, HLS, and DASH endpoints return 404. Contact SpactureAI for API documentation.")
        return false
    }
    
    private fun tryWhipSignaling(streamUrl: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Trying WHIP signaling...")
            val baseUrl = extractHttpBaseUrl(streamUrl)
            val whipUrl = "$baseUrl/whip"
            
            val url = URL(whipUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/sdp")
            connection.setRequestProperty("Accept", "application/sdp")
            connection.doOutput = true
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            
            // Send SDP offer
            connection.outputStream.use { os ->
                os.write(offer.description.toByteArray())
            }
            
            val responseCode = connection.responseCode
            Log.d(TAG, "WHIP response code: $responseCode")
            
            if (responseCode == 200 || responseCode == 201) {
                // Read SDP answer
                val answer = connection.inputStream.bufferedReader().use { it.readText() }
                Log.d(TAG, "Received SDP answer via WHIP: ${answer.take(100)}...")
                
                // Set remote description
                val answerSdp = SessionDescription(SessionDescription.Type.ANSWER, answer)
                peerConnection?.setRemoteDescription(object : SdpObserver {
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onSetSuccess() {
                        Log.d(TAG, "WHIP signaling successful!")
                    }
                    override fun onCreateFailure(p0: String?) {}
                    override fun onSetFailure(p0: String?) {
                        Log.e(TAG, "Failed to set remote description from WHIP: $p0")
                    }
                }, answerSdp)
                
                return true
            }
            
            false
        } catch (e: Exception) {
            Log.e(TAG, "WHIP signaling failed: ${e.message}")
            false
        }
    }
    
    private fun tryWhepSignaling(streamUrl: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "=== ATTEMPTING WHEP SIGNALING ===")
            val baseUrl = extractHttpBaseUrl(streamUrl)
            val streamPath = streamUrl.substringAfter(baseUrl)
            
            // WHEP endpoints to try for receiving streams
            val whepEndpoints = listOf(
                "$baseUrl/whep",                    // Standard WHEP endpoint
                "$baseUrl/whep$streamPath",         // WHEP with stream path
                "$baseUrl/api/whep",                // API WHEP endpoint
                "$baseUrl/api/whep$streamPath",     // API WHEP with stream path
                "$baseUrl/webrtc/whep",             // WebRTC WHEP endpoint
                "$baseUrl/webrtc/whep$streamPath",  // WebRTC WHEP with stream path
                "$baseUrl/play",                    // Simple play endpoint
                "$baseUrl/play$streamPath",         // Play with stream path
                "$baseUrl/receive",                 // Receive endpoint
                "$baseUrl/receive$streamPath"       // Receive with stream path
            )
            
            for (whepUrl in whepEndpoints) {
                Log.d(TAG, "Trying WHEP endpoint: $whepUrl")
                if (attemptWhepExchange(whepUrl, offer)) {
                    Log.d(TAG, "WHEP signaling successful!")
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.e(TAG, "WHEP signaling error: ${e.message}")
            false
        }
    }
    
    private fun attemptWhepExchange(whepUrl: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Attempting WHEP exchange at: $whepUrl")
            
            val url = URL(whepUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/sdp")
            connection.setRequestProperty("Accept", "application/sdp")
            connection.setRequestProperty("User-Agent", "React-Native-Unified-WebRTC/1.0")
            connection.doOutput = true
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            
            // Send the SDP offer
            connection.outputStream.use { os ->
                os.write(offer.description.toByteArray())
            }
            
            val responseCode = connection.responseCode
            Log.d(TAG, "WHEP response code: $responseCode for $whepUrl")
            
            if (responseCode == 200 || responseCode == 201) {
                // Read the SDP answer
                val answerSdp = connection.inputStream.bufferedReader().use { it.readText() }
                Log.d(TAG, "WHEP answer SDP received: ${answerSdp.take(100)}...")
                
                // Set remote description with the answer
                val remoteSdp = SessionDescription(SessionDescription.Type.ANSWER, answerSdp)
                peerConnection?.setRemoteDescription(object : SdpObserver {
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onSetSuccess() {
                        Log.d(TAG, "WHEP: Remote description set successfully!")
                    }
                    override fun onCreateFailure(p0: String?) {
                        Log.e(TAG, "WHEP: Create failure: $p0")
                    }
                    override fun onSetFailure(p0: String?) {
                        Log.e(TAG, "WHEP: Set remote description failed: $p0")
                    }
                }, remoteSdp)
                
                return true
            } else {
                val errorBody = try {
                    connection.errorStream?.bufferedReader()?.use { it.readText() } ?: 
                    connection.inputStream?.bufferedReader()?.use { it.readText() } ?: "No error details"
                } catch (e: Exception) {
                    "Could not read error: ${e.message}"
                }
                Log.e(TAG, "WHEP failed with response code: $responseCode")
                Log.e(TAG, "WHEP error response: $errorBody")
                emitConnectionError("WHEP failed: HTTP $responseCode - $errorBody")
                return false
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "WHEP exchange failed: ${e.message}")
            false
        }
    }
    
    private fun tryDirectSdpExchange(streamUrl: String, streamId: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Trying direct SDP exchange...")
            val baseUrl = extractHttpBaseUrl(streamUrl)
            
            // Try common SDP exchange endpoints
            val endpoints = listOf(
                "$baseUrl/api/webrtc/offer",
                "$baseUrl/webrtc/offer", 
                "$baseUrl/offer",
                "$baseUrl/$streamId/offer",
                "$baseUrl/stream/$streamId/offer"
            )
            
            for (endpoint in endpoints) {
                if (attemptSdpExchange(endpoint, offer)) {
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Direct SDP exchange failed: ${e.message}")
            false
        }
    }
    
    private fun tryStreamingServiceEndpoints(streamUrl: String, streamId: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Trying streaming service specific endpoints...")
            
            // Try endpoints specific to this streaming service
            val endpoints = listOf(
                "https://live.spacture.ai:8443/api/webrtc/play",
                "https://live.spacture.ai:8443/webrtc/play",
                "https://live.spacture.ai:8443/play/$streamId",
                "https://live.spacture.ai:8443/stream/play"
            )
            
            for (endpoint in endpoints) {
                if (attemptStreamingServiceCall(endpoint, streamId, offer)) {
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Streaming service endpoints failed: ${e.message}")
            false
        }
    }
    
    private fun extractHttpBaseUrl(streamUrl: String): String {
        return try {
            val uri = URI(streamUrl)
            "${uri.scheme}://${uri.host}:${uri.port}"
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting HTTP base URL: ${e.message}")
            "https://live.spacture.ai:8443"
        }
    }
    
    private fun extractBaseUrl(streamUrl: String): String {
        return try {
            val uri = URI(streamUrl)
            val scheme = if (uri.scheme == "https") "wss" else "ws"
            "$scheme://${uri.host}:${uri.port}"
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting base URL: ${e.message}")
            "wss://live.spacture.ai:8443"
        }
    }
    
    private fun attemptSdpExchange(endpoint: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Attempting SDP exchange at: $endpoint")
            
            val url = URL(endpoint)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            
            val requestBody = JSONObject().apply {
                put("type", "offer")
                put("sdp", offer.description)
            }
            
            connection.outputStream.use { os ->
                os.write(requestBody.toString().toByteArray())
            }
            
            val responseCode = connection.responseCode
            Log.d(TAG, "SDP exchange response code: $responseCode for $endpoint")
            
            if (responseCode == 200) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                Log.d(TAG, "SDP exchange response: ${response.take(200)}...")
                
                val jsonResponse = JSONObject(response)
                if (jsonResponse.has("sdp")) {
                    val answerSdp = SessionDescription(SessionDescription.Type.ANSWER, jsonResponse.getString("sdp"))
                    peerConnection?.setRemoteDescription(object : SdpObserver {
                        override fun onCreateSuccess(p0: SessionDescription?) {}
                        override fun onSetSuccess() {
                            Log.d(TAG, "SDP exchange successful!")
                        }
                        override fun onCreateFailure(p0: String?) {}
                        override fun onSetFailure(p0: String?) {
                            Log.e(TAG, "Failed to set remote description: $p0")
                        }
                    }, answerSdp)
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "SDP exchange failed for $endpoint: ${e.message}")
            false
        }
    }
    
    private fun attemptStreamingServiceCall(endpoint: String, streamId: String, offer: SessionDescription): Boolean {
        return try {
            Log.d(TAG, "Attempting streaming service call: $endpoint")
            
            val url = URL(endpoint)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            
            val requestBody = JSONObject().apply {
                put("streamId", streamId)
                put("offer", JSONObject().apply {
                    put("type", "offer")
                    put("sdp", offer.description)
                })
            }
            
            connection.outputStream.use { os ->
                os.write(requestBody.toString().toByteArray())
            }
            
            val responseCode = connection.responseCode
            Log.d(TAG, "Streaming service response code: $responseCode for $endpoint")
            
            if (responseCode == 200) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                Log.d(TAG, "Streaming service response: ${response.take(200)}...")
                
                val jsonResponse = JSONObject(response)
                if (jsonResponse.has("answer")) {
                    val answerObj = jsonResponse.getJSONObject("answer")
                    val answerSdp = SessionDescription(SessionDescription.Type.ANSWER, answerObj.getString("sdp"))
                    peerConnection?.setRemoteDescription(object : SdpObserver {
                        override fun onCreateSuccess(p0: SessionDescription?) {}
                        override fun onSetSuccess() {
                            Log.d(TAG, "Streaming service signaling successful!")
                        }
                        override fun onCreateFailure(p0: String?) {}
                        override fun onSetFailure(p0: String?) {
                            Log.e(TAG, "Failed to set remote description: $p0")
                        }
                    }, answerSdp)
                    return true
                }
            }
            
            false
        } catch (e: Exception) {
            Log.d(TAG, "Streaming service call failed for $endpoint: ${e.message}")
            false
        }
    }

    private fun sendWhepOffer(streamUrl: String) {
        Log.d(TAG, "=== SENDING WHEP OFFER ===")
        val localSdp = peerConnection?.localDescription
        if (localSdp == null) {
            Log.e(TAG, "No local SDP available for WHEP")
            return
        }
        
        Log.d(TAG, "Sending WHEP offer to: $streamUrl")
        Log.d(TAG, "SDP length: ${localSdp.description.length} chars")
        
        executor.execute {
            try {
                val url = URL(streamUrl)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/sdp")
                connection.setRequestProperty("Accept", "application/sdp")
                connection.doOutput = true
                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                
                // Send the SDP offer
                connection.outputStream.use { os ->
                    os.write(localSdp.description.toByteArray())
                }
                
                val responseCode = connection.responseCode
                Log.d(TAG, "WHEP response code: $responseCode")
                
                if (responseCode == 200 || responseCode == 201) {
                    // Read the SDP answer
                    val answerSdp = connection.inputStream.bufferedReader().use { it.readText() }
                    Log.d(TAG, "WHEP answer SDP received: ${answerSdp.take(100)}...")
                    
                    // Set remote description with the answer
                    val remoteSdp = SessionDescription(SessionDescription.Type.ANSWER, answerSdp)
                    peerConnection?.setRemoteDescription(object : SdpObserver {
                        override fun onCreateSuccess(p0: SessionDescription?) {}
                        override fun onSetSuccess() {
                            Log.d(TAG, "WHEP: Remote description set successfully!")
                            Log.d(TAG, "WebRTC connection established via WHEP!")
                        }
                        override fun onCreateFailure(p0: String?) {
                            Log.e(TAG, "WHEP: Create failure: $p0")
                        }
                        override fun onSetFailure(p0: String?) {
                            Log.e(TAG, "WHEP: Set remote description failed: $p0")
                            emitConnectionError("WHEP: Failed to set remote description: $p0")
                        }
                    }, remoteSdp)
                } else {
                    val errorBody = try {
                        connection.errorStream?.bufferedReader()?.use { it.readText() } ?: 
                        connection.inputStream?.bufferedReader()?.use { it.readText() } ?: "No error details"
                    } catch (e: Exception) {
                        "Could not read error: ${e.message}"
                    }
                    Log.e(TAG, "WHEP failed with response code: $responseCode")
                    Log.e(TAG, "WHEP error response: $errorBody")
                    emitConnectionError("WHEP failed: HTTP $responseCode - $errorBody")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "WHEP exchange failed: ${e.message}")
                emitConnectionError("WHEP exchange failed: ${e.message}")
            }
        }
    }
    
    private fun emitLocalSdp(sdp: SessionDescription) {
        val params = Arguments.createMap().apply {
            putString("sdp", sdp.description)
            putString("type", sdp.type.canonicalForm())
        }
        (context as? ThemedReactContext)?.getJSModule(RCTEventEmitter::class.java)?.receiveEvent(id, "onLocalSdpReady", params)
    }
    
    private fun emitIceCandidate(candidate: IceCandidate) {
        val params = Arguments.createMap().apply {
            putString("candidate", candidate.sdp)
            putString("sdpMid", candidate.sdpMid)
            putDouble("sdpMLineIndex", candidate.sdpMLineIndex.toDouble())
        }
        (context as? ThemedReactContext)?.getJSModule(RCTEventEmitter::class.java)?.receiveEvent(id, "onIceCandidateReady", params)
    }

    private fun setupPeerConnection() {
        Log.d(TAG, "Setting up PeerConnection...")
        
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("turn:52.0.202.78:3478")
                .setUsername("dummy-password")
                .setPassword("dummy")
                .createIceServer()
        )
        
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
        }
        
        peerConnection = peerConnectionFactory?.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onSignalingChange(newState: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState?) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(newState: PeerConnection.IceGatheringState?) {
                Log.d(TAG, "ICE gathering state: $newState")
                if (newState == PeerConnection.IceGatheringState.COMPLETE) {
                    // ICE gathering complete - ready to send offer for WHEP
                    iceGatheringComplete = true
                    pendingStreamUrl?.let { url ->
                        if (url.contains("/whep")) {
                            // This is a direct WHEP URL, send offer now
                            sendWhepOffer(url)
                        }
                    }
                }
            }
            
            override fun onIceCandidate(candidate: IceCandidate?) {
                candidate?.let {
                    Log.d(TAG, "ICE candidate: ${it.sdp}")
                    emitIceCandidate(it)
                }
            }
            
            override fun onAddTrack(receiver: RtpReceiver?, mediaStreams: Array<out MediaStream>?) {
                Log.d(TAG, "onAddTrack called with receiver: $receiver")
                mediaStreams?.forEach { stream ->
                    Log.d(TAG, "Remote stream added: ${stream.id}")
                    stream.videoTracks?.forEach { videoTrack ->
                        Log.d(TAG, "Adding video track to renderer")
                        Handler(Looper.getMainLooper()).post {
                            surfaceViewRenderer?.let { renderer ->
                                videoTrack.addSink(renderer)
                                Log.d(TAG, "Video track added to renderer")
                            }
                        }
                    }
                }
            }
            
            override fun onAddStream(stream: MediaStream?) {
                Log.d(TAG, "onAddStream called: ${stream?.id}")
                stream?.videoTracks?.forEach { videoTrack ->
                    Log.d(TAG, "Adding video track from stream to renderer")
                    Handler(Looper.getMainLooper()).post {
                        surfaceViewRenderer?.let { renderer ->
                            videoTrack.addSink(renderer)
                            Log.d(TAG, "Video track from stream added to renderer")
                        }
                    }
                }
            }
            
            override fun onRemoveStream(stream: MediaStream?) {
                Log.d(TAG, "Stream removed")
            }
            
            override fun onDataChannel(dataChannel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onTrack(transceiver: RtpTransceiver?) {}
            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState?) {}
        })
        
        // Add receive-only video transceiver (matching web example)
        peerConnection?.addTransceiver(
            MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
            RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY)
        )
        
        Log.d(TAG, "PeerConnection setup complete")
    }

    fun dispose() {
        Log.d(TAG, "Disposing WebRTC resources")
        
        executor.execute {
            try {
                remoteVideoTrack?.removeSink(surfaceViewRenderer)
                localVideoTrack?.removeSink(surfaceViewRenderer)
                remoteVideoTrack?.dispose()
                localVideoTrack?.dispose()
                
                post {
                    surfaceViewRenderer?.release()
                    surfaceViewRenderer = null
                }
                
                peerConnection?.dispose()
                peerConnection = null
                
                Log.d(TAG, "WebRTC resources disposed")
            } catch (e: Exception) {
                Log.e(TAG, "Error disposing resources: ${e.message}")
            }
        }
    }

    // SdpObserver implementation
    open class SdpObserverAdapter : SdpObserver {
        override fun onCreateSuccess(sdp: SessionDescription?) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(error: String?) {}
        override fun onSetFailure(error: String?) {}
    }
}
