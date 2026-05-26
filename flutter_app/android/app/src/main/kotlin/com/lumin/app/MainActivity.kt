package com.lumin.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyKeyguardFlagsForIntent(intent)
        captureCallExtras(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyKeyguardFlagsForIntent(intent)
        captureCallExtras(intent)

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

    companion object {
        const val CHANNEL = "familylink/calls"
    }
}
