package com.lumin.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
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
    private var ringtone: MediaPlayer? = null
    private var vibrator: Vibrator? = null
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

        // If a second incoming arrives while one is already ringing, ignore the
        // newcomer here — CallNotifier on the Flutter side will respond with
        // call:busy via the socket. We keep ringing the original one.
        if (activeCallId != null && activeCallId != callId) {
            Log.i(TAG, "already ringing for $activeCallId; ignoring $callId")
            return
        }

        activeCallId = callId
        ensureCallNotificationChannel()

        val notif = buildIncomingNotification(intent)
        val foregroundType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            } else {
                0
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && foregroundType != 0) {
            startForeground(CALL_NOTIFICATION_ID, notif, foregroundType)
        } else {
            startForeground(CALL_NOTIFICATION_ID, notif)
        }

        acquireWakeLockBounded()
        startRingingTone()
        startVibration()
        armRingTimeout()

        // If the Flutter engine is already alive (app foregrounded), forward
        // the FCM payload over the bus so the in-app UI matches. The CallNotifier
        // will dedup by call_id against any socket call:incoming it also receives.
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

        val acceptPending = PendingIntent.getBroadcast(
            this,
            REQUEST_ACCEPT,
            buildActionIntent(intent, CallActionReceiver.ACTION_ACCEPT, callId),
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

    private fun startRingingTone() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone = MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(this@CallService, uri)
                isLooping = true
                // setVolume is no-op for the ringer stream on most OEMs;
                // ringer-mode is respected by the audio attrs above.
                prepare()
                start()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "ringtone failed: ${t.message}")
        }
    }

    private fun startVibration() {
        try {
            val v: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = v
            // Skip vibration when the ringer is silent/vibrate-off respectively.
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (am.ringerMode == AudioManager.RINGER_MODE_SILENT) return

            val pattern = longArrayOf(0, 800, 1000, 800, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(pattern, 0)
                v?.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(pattern, 0)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "vibration failed: ${t.message}")
        }
    }

    private fun stopRinging() {
        try {
            ringtone?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Throwable) { /* ignore */ }
        ringtone = null
        try {
            vibrator?.cancel()
        } catch (_: Throwable) { /* ignore */ }
        vibrator = null
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

    private fun armRingTimeout() {
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
        handler.postDelayed(runnable, RING_TIMEOUT_MS)
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

    private fun postMissedCallNotification(callId: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notif = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText("Tap to open Lumin")
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        nm.notify(MISSED_CALL_NOTIFICATION_ID_BASE + callId.hashCode(), notif)
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
            enableVibration(true)
            setBypassDnd(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                attrs,
            )
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
