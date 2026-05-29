package com.lumin.app

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Prompt 15 — bridges the native call layer (FcmService, CallService, CallActionReceiver)
 * to Flutter via a single MethodChannel.
 *
 * Two main responsibilities:
 *   1. When launched from a CallService full-screen intent (or a notification action),
 *      capture the call payload from the launch intent and stash it so Flutter can
 *      pull it on startup via getInitialCallData().
 *   2. Expose the methods Flutter calls to drive the native side: acceptCall,
 *      declineCall, endCall, stopCallService, setEngineAlive.
 *
 * showWhenLocked / turnScreenOn are toggled on at runtime only when the launch
 * intent carries [CallService.EXTRA_FROM_CALL_NOTIFICATION], so a plain launcher
 * tap can't bypass the keyguard.
 */
class MainActivity : FlutterFragmentActivity() {
    private var methodChannel: MethodChannel? = null

    /** Latest pending incoming-call payload (consumed once by Flutter on startup). */
    private var pendingCallData: Map<String, Any?>? = null

    /** Pending native action ('accept' | 'decline' | null) carried in the launch intent. */
    private var pendingCallAction: String? = null

    /**
     * True while a call screen is up — lets [onUserLeaveHint] auto-enter
     * Picture-in-Picture when the user backgrounds the app mid-call. Set from
     * Flutter via the "setPipActive" channel method.
     */
    private var pipActive = false

    /** conversation_id from a tapped message notification, pending until the
     * Flutter engine pulls it via "getInitialConversation" (cold start). */
    private var pendingConversationId: String? = null

    /**
     * Proximity-screen-off wake lock — acquired while a voice call is active
     * (not video calls). When the user puts the phone to their ear the screen
     * blanks and touch is ignored; when they pull it away, screen comes back.
     * Held outside any composable / Flutter widget lifecycle so it survives
     * route transitions during the call.
     */
    private var proximityWakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyKeyguardFlagsForIntent(intent)
        captureCallExtras(intent)
        captureConversationExtra(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyKeyguardFlagsForIntent(intent)
        captureCallExtras(intent)
        captureConversationExtra(intent)

        // If the engine is already alive, forward the action immediately.
        val payload = pendingCallData
        val action = pendingCallAction
        if (payload != null) {
            methodChannel?.invokeMethod(
                "incomingCall",
                payload + mapOf("native_action" to action),
            )
            pendingCallData = null
            pendingCallAction = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        NativeCallBus.attach(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialCallData" -> {
                    val payload = pendingCallData
                    val action = pendingCallAction
                    pendingCallData = null
                    pendingCallAction = null
                    if (payload == null) {
                        result.success(null)
                    } else {
                        result.success(payload + mapOf("native_action" to action))
                    }
                }
                "acceptCall" -> {
                    val callId = call.argument<String>("call_id") ?: ""
                    CallService.stopForCallId(this, callId)
                    result.success(true)
                }
                "declineCall" -> {
                    val callId = call.argument<String>("call_id") ?: ""
                    CallService.stopForCallId(this, callId)
                    result.success(true)
                }
                "endCall" -> {
                    val callId = call.argument<String>("call_id") ?: ""
                    CallService.stopForCallId(this, callId)
                    result.success(true)
                }
                "stopCallService" -> {
                    CallService.stopAll(this)
                    result.success(true)
                }
                "startIncomingCallService" -> {
                    // Flutter received a socket call:incoming while the app
                    // was backgrounded — spin up the native ringer/full-screen
                    // activity right away rather than waiting for FCM to land
                    // (FCM can take 10–30 s under battery optimization, by
                    // which point the 30 s server-side ring window is gone).
                    //
                    // CallService.handleIncoming dedups by call_id, so it's
                    // safe even if FCM also fires for the same call.
                    val raw = call.arguments
                    if (raw is Map<*, *>) {
                        val data = HashMap<String, String?>()
                        for ((k, v) in raw) {
                            if (k is String) {
                                data[k] = v?.toString()
                            }
                        }
                        if (data[CallService.EXTRA_CALL_ID].isNullOrBlank()) {
                            result.error("BAD_ARGS", "call_id is required", null)
                        } else {
                            CallService.startIncoming(this, data)
                            result.success(true)
                        }
                    } else {
                        result.error("BAD_ARGS", "expected a Map payload", null)
                    }
                }
                "setEngineAlive" -> {
                    val alive = call.argument<Boolean>("alive") ?: false
                    NativeCallBus.setEngineAlive(alive)
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(BatteryOptimization.isIgnoring(this))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    BatteryOptimization.requestIgnore(this)
                    result.success(true)
                }
                "openAppSettings" -> {
                    BatteryOptimization.openAppSettings(this)
                    result.success(true)
                }
                "getOemHints" -> {
                    result.success(BatteryOptimization.getOemHints())
                }
                "openOemAutoStartSettings" -> {
                    val opened = BatteryOptimization.openOemAutoStartSettings(this)
                    result.success(opened)
                }
                "setVoiceCallVolumeStream" -> {
                    // While true, hardware volume buttons control the
                    // STREAM_VOICE_CALL (in-call) audio level instead of the
                    // default media stream. The previous behavior was that
                    // turning down volume during a call would change ringer
                    // volume instead of call volume — confusing and wrong.
                    //
                    // setVolumeControlStream is per-Activity; restoring to
                    // USE_DEFAULT_STREAM_TYPE on call end resets it to media.
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    volumeControlStream = if (enabled) {
                        AudioManager.STREAM_VOICE_CALL
                    } else {
                        AudioManager.USE_DEFAULT_STREAM_TYPE
                    }
                    result.success(true)
                }
                "setProximityAware" -> {
                    // Acquire PROXIMITY_SCREEN_OFF_WAKE_LOCK during voice
                    // calls only (NOT video). When the proximity sensor
                    // detects the phone is near the user's ear, the screen
                    // blanks and touch input is suspended — same as the
                    // native dialer.
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) acquireProximityLock() else releaseProximityLock()
                    result.success(true)
                }
                "startActiveCallService" -> {
                    // FIX 7: Flutter has transitioned the call to connected.
                    // Start a foreground service so Android doesn't kill the
                    // process when the user backgrounds the app.
                    val callId = call.argument<String>("call_id")
                    val peerName = call.argument<String>("peer_name") ?: "Call"
                    val callType = call.argument<String>("call_type") ?: "audio"
                    if (callId.isNullOrBlank()) {
                        result.error("BAD_ARGS", "call_id required", null)
                    } else {
                        ActiveCallService.startActiveCall(
                            this, callId, peerName, callType,
                        )
                        result.success(true)
                    }
                }
                "stopActiveCallService" -> {
                    // FIX 7: Call ended (any reason). Stop the persistent
                    // notification + foreground service.
                    ActiveCallService.stop(this)
                    result.success(true)
                }
                "setPipActive" -> {
                    // Flutter toggles this while a call screen is foregrounded
                    // so backgrounding the app auto-enters Picture-in-Picture.
                    pipActive = call.argument<Boolean>("active") ?: false
                    result.success(true)
                }
                "enterPip" -> {
                    // Explicit request (e.g. the minimize button). Returns
                    // false if the device/OS can't do PiP so Flutter can fall
                    // back to its in-app mini view.
                    result.success(enterPipMode())
                }
                "getInitialConversation" -> {
                    // Cold-start: Flutter pulls the conversation_id from a
                    // tapped message notification so it can route to the chat.
                    val c = pendingConversationId
                    pendingConversationId = null
                    result.success(c)
                }
                else -> result.notImplemented()
            }
        }
        // Engine is now attached → mark alive so CallActionReceiver knows to use
        // the MethodChannel path instead of relaunching MainActivity.
        NativeCallBus.setEngineAlive(true)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NativeCallBus.setEngineAlive(false)
        NativeCallBus.detach()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ── Internal ────────────────────────────────────────────────────────────────

    private fun captureCallExtras(intent: Intent?) {
        if (intent == null) return
        val fromCallNotif = intent.getBooleanExtra(
            CallService.EXTRA_FROM_CALL_NOTIFICATION, false,
        )
        if (!fromCallNotif) return

        val data = HashMap<String, Any?>()
        for (key in CallService.PAYLOAD_KEYS) {
            val v = intent.getStringExtra(key)
            if (v != null) data[key] = v
        }
        if (data.isNotEmpty()) {
            pendingCallData = data
            pendingCallAction = intent.getStringExtra(CallService.EXTRA_NATIVE_ACTION)
        }
    }

    /**
     * Capture a `conversation_id` extra from a tapped message notification
     * (posted by FcmService). If the engine is live, route immediately; else
     * stash it for Flutter to pull on startup via "getInitialConversation".
     */
    private fun captureConversationExtra(intent: Intent?) {
        val convId = intent?.getStringExtra("conversation_id")
            ?.takeIf { it.isNotBlank() } ?: return
        val channel = methodChannel
        if (channel != null && NativeCallBus.isEngineAlive()) {
            channel.invokeMethod("openConversation", convId)
        } else {
            pendingConversationId = convId
        }
    }

    /**
     * Turn on showWhenLocked / turnScreenOn only when we were launched from a
     * call notification — never for a plain launcher tap.
     */
    @Suppress("DEPRECATION")
    private fun applyKeyguardFlagsForIntent(intent: Intent?) {
        val fromCallNotif = intent?.getBooleanExtra(
            CallService.EXTRA_FROM_CALL_NOTIFICATION, false,
        ) ?: false
        if (!fromCallNotif) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            // Ask the system to dismiss the keyguard if it's not secure.
            val km = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
    }

    // ── Proximity wake lock ─────────────────────────────────────────────────

    @Suppress("DEPRECATION")  // ON_AFTER_RELEASE flag deprecated but only on R+; harmless.
    private fun acquireProximityLock() {
        try {
            if (proximityWakeLock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                Log.w(TAG, "device has no proximity sensor; skipping wake lock")
                return
            }
            val wl = pm.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "lumin:call_proximity",
            )
            wl.setReferenceCounted(false)
            wl.acquire()
            proximityWakeLock = wl
        } catch (t: Throwable) {
            Log.w(TAG, "proximity wake lock acquire failed: ${t.message}")
        }
    }

    private fun releaseProximityLock() {
        try {
            // Release with ON_AFTER_RELEASE flag = turn the screen ON when
            // released (e.g. call ended while phone still at ear).
            val wl = proximityWakeLock
            if (wl != null && wl.isHeld) {
                @Suppress("DEPRECATION")
                wl.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "proximity wake lock release failed: ${t.message}")
        }
        proximityWakeLock = null
    }

    // ── Picture-in-Picture ──────────────────────────────────────────────────

    /**
     * Auto-enter PiP when the user leaves the app (Home/Recents) during a call.
     * Only fires when a call screen has marked itself active via "setPipActive".
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipActive) enterPipMode()
    }

    /** Tell Flutter so the call screen can hide controls / show only video. */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    /** Enter PiP with a portrait phone aspect. Returns false when unsupported. */
    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(
                PackageManager.FEATURE_PICTURE_IN_PICTURE,
            )
        ) {
            return false
        }
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        } catch (t: Throwable) {
            Log.w(TAG, "enterPip failed: ${t.message}")
            false
        }
    }

    override fun onDestroy() {
        releaseProximityLock()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "familylink/calls"
        private const val TAG = "MainActivity"
    }
}
