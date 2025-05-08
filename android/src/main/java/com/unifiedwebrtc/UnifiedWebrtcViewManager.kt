package com.unifiedwebrtc

import android.graphics.Color
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.UnifiedWebrtcViewManagerInterface
import com.facebook.react.viewmanagers.UnifiedWebrtcViewManagerDelegate

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
    view?.setBackgroundColor(Color.parseColor(color))
  }

  companion object {
    const val NAME = "UnifiedWebrtcView"
  }
}
