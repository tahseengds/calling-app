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
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * FIX 7 — foreground service that keeps a *connected* VoIP call alive when
 * the user backgrounds the app or locks the screen.
 *
 * This is distinct from [CallService] (which handles INCOMING ringing — the
 * pre-pickup foreground service). ActiveCallService runs from the moment
 * ICE reports connected until the call ends, keeping the process priority
 * high enough that Android won't reclaim it (and therefore won't kill the
 * WebRTC pipeline running the call).
 *
 * Notification:
 *   - Ongoing (non-dismissable while service is foreground)
 *   - Title = peer name
 *   - Action: "Hang up" → broadcasts ACTION_HANGUP → MainActivity routes the
 *     event back to Flutter via the existing NativeCallBus, which invokes
 *     CallNotifier.endCall().
 *
 * Foreground service type: phoneCall + microphone (camera too, for video
 * calls — declared in the manifest as phoneCall|microphone|camera which
 * covers all our cases).
 *
 * Lifecycle: started via [startActiveCall] (called from MainActivity's
 * method channel handler), stopped via [stop]. Returns START_NOT_STICKY
 * because a killed service shouldn't auto-resurrect — the WebRTC peer
 * connection is already dead by then.
 */
class ActiveCallService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> stopSelfCleanly()
            else -> { /* unknown action — ignore */ }
        }
        return START_NOT_STICKY
    }

    private fun handleStart(intent: Intent) {
        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: run {
            Log.w(TAG, "start intent missing call_id; aborting")
            stopSelfCleanly()
            return
        }
        ensureChannel()
        val notif = buildOngoingNotification(intent, callId)
        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            } else {
                0
            }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && type != 0) {
                startForeground(NOTIFICATION_ID, notif, type)
            } else {
                startForeground(NOTIFICATION_ID, notif)
            }
        } catch (t: Throwable) {
            // ActiveCallService is normally started right after the user answers
            // (app foregrounded → eligible for a microphone FGS). If it's somehow
            // denied, don't crash: show the ongoing-call notification directly and
            // stop so the "didn't call startForeground in time" watchdog can't
            // fire. The Flutter/WebRTC layer still drives the live call.
            Log.w(TAG, "startForeground denied (${t.javaClass.simpleName}): ${t.message}; notification fallback")
            try {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(NOTIFICATION_ID, notif)
            } catch (_: Throwable) { /* ignore */ }
            stopSelfCleanly()
            return
        }
    }

    private fun buildOngoingNotification(intent: Intent, callId: String): Notification {
        val peerName = intent.getStringExtra(EXTRA_PEER_NAME) ?: "Call"
        val callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: "audio"
        val typeLabel = if (callType == "video") "Video call" else "Voice call"

        // Tapping the notification body re-opens the app (which already
        // routes the user back to the live call screen via the global call
        // observer in app.dart).
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tapPending = PendingIntent.getActivity(
            this,
            REQUEST_TAP,
            tapIntent,
            pendingFlags(),
        )

        // "Hang up" notification action — broadcasts to CallActionReceiver,
        // which forwards to NativeCallBus → Flutter → CallNotifier.endCall().
        val hangupIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_HANGUP
            putExtra(EXTRA_CALL_ID, callId)
        }
        val hangupPending = PendingIntent.getBroadcast(
            this,
            REQUEST_HANGUP,
            hangupIntent,
            pendingFlags(),
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(peerName)
            .setContentText("$typeLabel in progress")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)  // not noisy — already in-call
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setUsesChronometer(true)  // shows live elapsed time
            .setContentIntent(tapPending)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Hang up",
                hangupPending,
            )
            .build()
    }

    private fun stopSelfCleanly() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Active calls",
            NotificationManager.IMPORTANCE_LOW,  // silent — call is already in progress
        ).apply {
            description = "Persistent notification shown while a call is ongoing"
            setShowBadge(false)
            // No sound/vibration — incoming-ringer channel handles that.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
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
        private const val TAG = "ActiveCallService"
        const val CHANNEL_ID = "active_calls"
        const val NOTIFICATION_ID = 0x10C5

        const val REQUEST_TAP = 200
        const val REQUEST_HANGUP = 201

        const val ACTION_START = "com.lumin.app.action.ACTIVE_START"
        const val ACTION_STOP = "com.lumin.app.action.ACTIVE_STOP"

        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_PEER_NAME = "peer_name"
        const val EXTRA_CALL_TYPE = "call_type"

        /** Start (or update) the active-call foreground service. */
        fun startActiveCall(
            ctx: Context,
            callId: String,
            peerName: String,
            callType: String,
        ) {
            val intent = Intent(ctx, ActiveCallService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_PEER_NAME, peerName)
                putExtra(EXTRA_CALL_TYPE, callType)
            }
            ContextCompat.startForegroundService(ctx, intent)
        }

        /** Stop the active-call foreground service unconditionally. */
        fun stop(ctx: Context) {
            val intent = Intent(ctx, ActiveCallService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                ctx.startService(intent)
            } catch (_: Throwable) { /* ignore — service likely already gone */ }
        }
    }
}
