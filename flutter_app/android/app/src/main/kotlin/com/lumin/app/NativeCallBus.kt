package com.lumin.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Prompt 15 — process-wide singleton that lets background components
 * (FcmService, CallService, CallActionReceiver) push events to Flutter
 * when the engine happens to be alive.
 *
 * Holds a soft reference to the active MethodChannel. When the engine is
 * dead the senders fall back to launching MainActivity with extras and
 * letting Flutter pull state via getInitialCallData().
 *
 * Thread-safety: all channel invocations are dispatched on the main looper
 * because MethodChannel.invokeMethod must be called on the UI thread.
 */
object NativeCallBus {
    @Volatile private var channel: MethodChannel? = null
    @Volatile private var engineAlive: Boolean = false

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(c: MethodChannel) {
        channel = c
    }

    fun detach() {
        channel = null
    }

    fun setEngineAlive(alive: Boolean) {
        engineAlive = alive
    }

    fun isEngineAlive(): Boolean = engineAlive && channel != null

    /** Push an event to Flutter. Returns true if delivered (engine alive). */
    fun invoke(method: String, args: Map<String, Any?>?): Boolean {
        val c = channel ?: return false
        if (!engineAlive) return false
        mainHandler.post { c.invokeMethod(method, args) }
        return true
    }
}
