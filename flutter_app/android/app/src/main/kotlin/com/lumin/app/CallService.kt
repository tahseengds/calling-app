package com.lumin.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Prompt 15 — foreground service that rings the device for an incoming call
 * while the app is backgrounded or fully killed.
 *
 * Lifecycle:
 *   1. onStartCommand(action = ACTION_INCOMING) — startForeground() within
 *      milliseconds, acquire a partial wake lock, play ringtone + vibrate,
 *      arm a 45 s ring timeout.
 *   2. CallActionReceiver fires ACTION_ACCEPT / ACTION_DECLINE → stopForCallId
 *      tears everything down, releases the wake lock, cancels the timer.
 *   3. ringTimeout expires → posts a missed-call notification and stops.
 *
 * Returns START_NOT_STICKY so a killed service is never auto-restarted —
 * a missed call should stay missed.
 */
class CallService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ringTimeoutRunnable: Runnable? = null

    /** call_id this service instance is currently ringing for. */
    private var activeCallId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_INCOMING -> handleIncoming(intent)
            ACTION_STOP -> {
                val callId = intent.getStringExtra(EXTRA_CALL_ID)
                if (callId == null || callId == activeCallId) {
                    stopRinging()
                    stopSelfCleanly()
                }
            }
            else -> { /* unknown action — ignore */ }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopRinging()
        releaseWakeLock()
        super.onDestroy()
    }

    // ── Incoming flow ───────────────────────────────────────────────────────────

    private fun handleIncoming(intent: Intent) {
        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: run {
            Log.w(TAG, "incoming intent missing call_id; aborting")
            stopSelfCleanly()
            return
        }

        // Idempotency check covers two cases:
        //   1. A second DIFFERENT incoming arrives while ringing — ignore the
        //      newcomer, CallNotifier responds with call:busy via the socket.
        //   2. The SAME callId arrives twice (e.g. FCM + Flutter-bridged start
        //      from a socket call:incoming) — also ignore so we don't restart
        //      the ringer, re-arm the timer, or post a second notification.
        if (activeCallId != null) {
            if (activeCallId != callId) {
                Log.i(TAG, "already ringing for $activeCallId; ignoring different callId $callId")
            } else {
                Log.i(TAG, "already ringing for $callId; ignoring duplicate start")
            }
            return
        }

        ensureCallNotificationChannel()

        // ── Stale / late-delivery guard ──────────────────────────────────────
        // OEM battery managers (notably MIUI/Xiaomi) can hold a force-closed
        // app's FCM for tens of seconds. If the incoming_call push lands after
        // the call's ring window has elapsed, the caller has already given up —
        // ringing now is a confusing "ghost ring". Using the server-stamped
        // initiated_at, ring only for the REMAINING window; if there's
        // essentially none left, show a missed call instead of ringing.
        val initiatedAt = intent.getStringExtra(EXTRA_INITIATED_AT)?.toLongOrNull()
        val ringMs: Long = if (initiatedAt != null) {
            RING_TIMEOUT_MS - (System.currentTimeMillis() - initiatedAt)
        } else {
            RING_TIMEOUT_MS
        }
        if (ringMs < STALE_RING_FLOOR_MS) {
            Log.i(TAG, "incoming_call delivered too late (ringMs=$ringMs); missed call, not ringing")
            // We were started via startForegroundService, so we MUST call
            // startForeground or the OS kills us with a timeout crash. Use a
            // silent missed-call notification (no full-screen intent → no ring,
            // no call screen), post a standalone copy, then stop.
            try {
                val placeholder = buildMissedCallNotification(callId)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        CALL_NOTIFICATION_ID,
                        placeholder,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                    )
                } else {
                    startForeground(CALL_NOTIFICATION_ID, placeholder)
                }
            } catch (_: Throwable) { /* FGS denied — the notify below still shows it */ }
            postMissedCallNotification(callId)
            stopSelfCleanly()
            return
        }

        activeCallId = callId

        val notif = buildIncomingNotification(intent)

        // Ring as a PHONE_CALL foreground service ONLY — never microphone. The
        // mic isn't needed until the user answers (ActiveCallService starts the
        // mic FGS then, while the app is foregrounded and therefore eligible).
        // On Android 14 a `microphone`-typed FGS started from the background —
        // which an FCM-triggered ring is — is disallowed and throws a
        // SecurityException; `phoneCall` is exempt because the app holds
        // MANAGE_OWN_CALLS. The whole start is wrapped so that if the platform
        // still denies the foreground start (general background-FGS restriction,
        // or the FCM grace window elapsed), we don't crash: we post the
        // incoming-call notification directly (its IMPORTANCE_HIGH calls channel
        // + full-screen intent still ring and present the UI), bridge to Flutter,
        // then stop cleanly so the "didn't call startForeground in time"
        // watchdog can't fire.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    CALL_NOTIFICATION_ID,
                    notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            } else {
                startForeground(CALL_NOTIFICATION_ID, notif)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "startForeground denied (${t.javaClass.simpleName}): ${t.message}; notification fallback")
            try {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(CALL_NOTIFICATION_ID, notif)
            } catch (_: Throwable) { /* ignore */ }
            forwardIncomingToFlutter(intent)
            stopSelfCleanly()
            return
        }

        acquireWakeLockBounded()
        // Single process-wide ringer (device ringtone + vibration). Shared with
        // the foreground IncomingCallScreen path so the two can never double up.
        IncomingRinger.start(this)
        // Ring only for the remaining window (full 45 s for a fresh push; less
        // if it was delivered late) so a late call stops when the caller's
        // window ends rather than ringing a fresh 45 s past it.
        armRingTimeout(ringMs)

        // If the Flutter engine is already alive (app foregrounded), forward
        // the FCM payload over the bus so the in-app UI matches. The CallNotifier
        // will dedup by call_id against any socket call:incoming it also receives.
        forwardIncomingToFlutter(intent)
    }

    /** Forward the incoming-call payload to the Flutter engine (if alive). */
    private fun forwardIncomingToFlutter(intent: Intent) {
        val payloadForFlutter = HashMap<String, Any?>().apply {
            for (key in PAYLOAD_KEYS) {
                val v = intent.getStringExtra(key)
                if (v != null) this[key] = v
            }
        }
        NativeCallBus.invoke("incomingCall", payloadForFlutter)
    }

    // ── Notification ────────────────────────────────────────────────────────────

    private fun buildIncomingNotification(intent: Intent): Notification {
        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        val callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: "audio"
        val callTypeLabel = if (callType == "video") "Video call" else "Voice call"

        // Full-screen intent → launches MainActivity over the keyguard.
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_FROM_CALL_NOTIFICATION, true)
            // Carry the call payload so Flutter can reconstruct it on cold start.
            for (key in PAYLOAD_KEYS) {
                val v = intent.getStringExtra(key)
                if (v != null) putExtra(key, v)
            }
        }
        val fullScreenPending = PendingIntent.getActivity(
            this,
            REQUEST_FULL_SCREEN,
            fullScreenIntent,
            pendingFlags(),
        )

        // Accept launches MainActivity DIRECTLY via a getActivity PendingIntent
        // rather than broadcasting to CallActionReceiver (which then did
        // context.startActivity). A background activity-start from a
        // BroadcastReceiver is blocked on Android 10+/14, so on a fully
        // backgrounded/killed device tapping "Accept" would connect the call with
        // no visible call screen. A notification action backed by getActivity is
        // allowed to bring the activity up. MainActivity reads native_action=accept
        // (warm: onNewIntent → callAction; cold: getInitialCallData) and the
        // CallNotifier accepts; its acceptCall then stops the ringer service.
        val acceptIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_FROM_CALL_NOTIFICATION, true)
            putExtra(EXTRA_NATIVE_ACTION, "accept")
            for (key in PAYLOAD_KEYS) {
                val v = intent.getStringExtra(key)
                if (v != null) putExtra(key, v)
            }
        }
        val acceptPending = PendingIntent.getActivity(
            this,
            REQUEST_ACCEPT,
            acceptIntent,
            pendingFlags(),
        )
        val declinePending = PendingIntent.getBroadcast(
            this,
            REQUEST_DECLINE,
            buildActionIntent(intent, CallActionReceiver.ACTION_DECLINE, callId),
            pendingFlags(),
        )

        return NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(callerName)
            .setContentText("Incoming $callTypeLabel")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            .setShowWhen(true)
            .setFullScreenIntent(fullScreenPending, true)
            .setContentIntent(fullScreenPending)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declinePending,
            )
            .addAction(
                android.R.drawable.ic_menu_call,
                "Accept",
                acceptPending,
            )
            .build()
    }

    private fun buildActionIntent(
        sourceIntent: Intent,
        action: String,
        callId: String,
    ): Intent {
        return Intent(this, CallActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_CALL_ID, callId)
            for (key in PAYLOAD_KEYS) {
                val v = sourceIntent.getStringExtra(key)
                if (v != null) putExtra(key, v)
            }
        }
    }

    // ── Ringtone & vibration ────────────────────────────────────────────────────

    private fun stopRinging() {
        // Ringer is owned by the shared single-instance IncomingRinger.
        IncomingRinger.stop()
        ringTimeoutRunnable?.let { handler.removeCallbacks(it) }
        ringTimeoutRunnable = null
    }

    // ── Wake lock (bounded) ─────────────────────────────────────────────────────

    private fun acquireWakeLockBounded() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            // ACQUIRE_CAUSES_WAKEUP is deprecated since API 32 — the OS now
            // unconditionally wakes the screen for full-screen-intent
            // notifications on the calls channel. A plain partial wake lock
            // is enough to keep the CPU running while we ring.
            val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lumin:call")
            wl.setReferenceCounted(false)
            // 2-minute upper bound — the OS releases it for us if we mis-handle.
            wl.acquire(WAKE_LOCK_TIMEOUT_MS)
            wakeLock = wl
        } catch (t: Throwable) {
            Log.w(TAG, "wake lock failed: ${t.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) { /* ignore */ }
        wakeLock = null
    }

    // ── Timeout ─────────────────────────────────────────────────────────────────

    private fun armRingTimeout(durationMs: Long) {
        ringTimeoutRunnable?.let { handler.removeCallbacks(it) }
        val runnable = Runnable {
            val callId = activeCallId
            stopRinging()
            if (callId != null) {
                postMissedCallNotification(callId)
            }
            stopSelfCleanly()
        }
        ringTimeoutRunnable = runnable
        handler.postDelayed(runnable, durationMs.coerceAtLeast(0L))
    }

    // ── Cleanup ─────────────────────────────────────────────────────────────────

    private fun stopSelfCleanly() {
        activeCallId = null
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** Build the missed-call notification (tap → call history). No full-screen
     * intent and on the now-silent calls channel, so it neither rings nor
     * launches the call screen — safe to also use as a stale-call FGS notif. */
    private fun buildMissedCallNotification(callId: String): Notification {
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("nav_route", "/call/history")
        }
        val tapPending = PendingIntent.getActivity(
            this,
            MISSED_CALL_NOTIFICATION_ID_BASE + callId.hashCode(),
            tapIntent,
            pendingFlags(),
        )
        return NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText("Tap to open Lumin")
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(tapPending)
            .build()
    }

    private fun postMissedCallNotification(callId: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            MISSED_CALL_NOTIFICATION_ID_BASE + callId.hashCode(),
            buildMissedCallNotification(callId),
        )
    }

    // ── Notification channel ────────────────────────────────────────────────────

    private fun ensureCallNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CALL_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming call notifications"
            setBypassDnd(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            // No channel sound/vibration: the ringtone + vibration are driven by
            // the shared IncomingRinger so there's exactly one source. A channel
            // sound here would play ON TOP of it (heads-up posts ring the channel
            // too), which is the double-ring we're eliminating.
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun pendingFlags(): Int {
        var f = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            f = f or PendingIntent.FLAG_IMMUTABLE
        }
        return f
    }

    companion object {
        private const val TAG = "CallService"

        // The notification channel (matches NotificationService.kChannelCalls).
        const val CALL_CHANNEL_ID = "calls"

        const val CALL_NOTIFICATION_ID = 0x10C1
        const val MISSED_CALL_NOTIFICATION_ID_BASE = 0x10C2

        const val REQUEST_FULL_SCREEN = 100
        const val REQUEST_ACCEPT = 101
        const val REQUEST_DECLINE = 102

        const val WAKE_LOCK_TIMEOUT_MS = 2L * 60L * 1000L // 2 minutes
        const val RING_TIMEOUT_MS = 45_000L
        // If a (delayed) incoming_call push leaves less than this much of the
        // ring window, the call is effectively over — show a missed call rather
        // than a brief "ghost ring". Also absorbs minor client/server clock skew.
        const val STALE_RING_FLOOR_MS = 3_000L

        // Intent actions
        const val ACTION_INCOMING = "com.lumin.app.action.INCOMING"
        const val ACTION_STOP = "com.lumin.app.action.STOP"

        // Intent extras — also re-used as keys in the Flutter payload map.
        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALLER_AVATAR = "caller_avatar"
        const val EXTRA_CALL_TYPE = "call_type"
        const val EXTRA_SDP_OFFER = "sdp_offer"
        const val EXTRA_SIGNAL_TOKEN = "signal_token"
        // Epoch-ms the call was placed (server-stamped). Lets a late ring be
        // capped to the remaining window / dropped if already expired.
        const val EXTRA_INITIATED_AT = "initiated_at"

        // Internal extras (not part of the call payload).
        const val EXTRA_FROM_CALL_NOTIFICATION = "from_call_notification"
        const val EXTRA_NATIVE_ACTION = "native_action" // 'accept' | 'decline'

        val PAYLOAD_KEYS = listOf(
            EXTRA_CALL_ID,
            EXTRA_CALLER_ID,
            EXTRA_CALLER_NAME,
            EXTRA_CALLER_AVATAR,
            EXTRA_CALL_TYPE,
            EXTRA_SDP_OFFER,
            EXTRA_SIGNAL_TOKEN,
            EXTRA_INITIATED_AT,
        )

        /** Convenience: start the foreground service for an incoming call. */
        fun startIncoming(
            ctx: Context,
            data: Map<String, String?>,
        ) {
            val intent = Intent(ctx, CallService::class.java).apply {
                action = ACTION_INCOMING
                for (key in PAYLOAD_KEYS) {
                    data[key]?.let { putExtra(key, it) }
                }
            }
            ContextCompat.startForegroundService(ctx, intent)
        }

        /** Stop a specific call (only if its id matches the active one). */
        fun stopForCallId(ctx: Context, callId: String) {
            val intent = Intent(ctx, CallService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_CALL_ID, callId)
            }
            // startService is safe even if the service isn't running — it
            // becomes a no-op once the receiver inspects activeCallId.
            try {
                ctx.startService(intent)
            } catch (_: Throwable) { /* ignore — service likely already gone */ }
        }

        /** Stop unconditionally. */
        fun stopAll(ctx: Context) {
            val intent = Intent(ctx, CallService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                ctx.startService(intent)
            } catch (_: Throwable) { /* ignore */ }
        }
    }
}
