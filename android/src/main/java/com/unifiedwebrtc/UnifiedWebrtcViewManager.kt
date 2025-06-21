package com.unifiedwebrtc

import android.graphics.Color
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.UnifiedWebrtcViewManagerInterface
import com.facebook.react.viewmanagers.UnifiedWebrtcViewManagerDelegate
import org.webrtc.IceCandidate
import org.webrtc.SessionDescription

@ReactModule(name = UnifiedWebrtcViewManager.NAME)
class UnifiedWebrtcViewManager : SimpleViewManager<UnifiedWebrtcView>(),
  UnifiedWebrtcViewManagerInterface<UnifiedWebrtcView> {
  private val mDelegate: ViewManagerDelegate<UnifiedWebrtcView>

  init {
    mDelegate = UnifiedWebrtcViewManagerDelegate(this)
  }

  override fun getDelegate(): ViewManagerDelegate<UnifiedWebrtcView>? {
    return mDelegate
  }

  override fun getName(): String {
    return NAME
  }

  public override fun createViewInstance(context: ThemedReactContext): UnifiedWebrtcView {
    return UnifiedWebrtcView(context)
  }

  @ReactProp(name = "color")
  override fun setColor(view: UnifiedWebrtcView?, color: String?) {
    // This prop might not be relevant for a WebRTC view that fills with video.
    // Consider removing if not used.
    view?.setBackgroundColor(Color.parseColor(color))
  }

  // Implement all required interface methods
  override fun playStream(view: UnifiedWebrtcView?, streamUrlOrSignalingInfo: String?) {
    streamUrlOrSignalingInfo?.let { view?.playStream(it) }
  }

  override fun createOffer(view: UnifiedWebrtcView?) {
    view?.createOffer()
  }

  override fun createAnswer(view: UnifiedWebrtcView?) {
    view?.createAnswer()
  }

  override fun setRemoteDescription(view: UnifiedWebrtcView?, sdp: String?, type: String?) {
    if (sdp != null && type != null) {
      val sessionDescription = SessionDescription(
        SessionDescription.Type.fromCanonicalForm(type),
        sdp
      )
      view?.setRemoteDescription(sessionDescription)
    }
  }

  override fun addIceCandidate(view: UnifiedWebrtcView?, candidateSdp: String?, sdpMLineIndex: Double, sdpMid: String?) {
    if (candidateSdp != null && sdpMid != null) {
      val iceCandidate = IceCandidate(sdpMid, sdpMLineIndex.toInt(), candidateSdp)
      view?.addIceCandidate(iceCandidate)
    }
  }

  override fun dispose(view: UnifiedWebrtcView?) {
    view?.dispose()
  }

  override fun receiveCommand(
    root: UnifiedWebrtcView,
    commandId: String,
    args: ReadableArray?
  ) {
    when (commandId) {
      "playStream" -> {
        val streamUrlOrSignalingInfo = args?.getString(0)
        playStream(root, streamUrlOrSignalingInfo)
      }
      "createOffer" -> {
        createOffer(root)
      }
      "createAnswer" -> {
        createAnswer(root)
      }
      "setRemoteDescription" -> {
        val sdp = args?.getString(0)
        val type = args?.getString(1)
        setRemoteDescription(root, sdp, type)
      }
      "addIceCandidate" -> {
        val candidateSdp = args?.getString(0)
        val sdpMLineIndex = args?.getDouble(1) ?: 0.0
        val sdpMid = args?.getString(2)
        addIceCandidate(root, candidateSdp, sdpMLineIndex, sdpMid)
      }
      "dispose" -> {
        dispose(root)
      }
      else -> {
        System.err.println("UnifiedWebrtcViewManager: Received unknown command: $commandId")
      }
    }
  }

  override fun onDropViewInstance(view: UnifiedWebrtcView) {
    super.onDropViewInstance(view)
    view.dispose()
  }

  companion object {
    const val NAME = "UnifiedWebrtcView"
  }
}
