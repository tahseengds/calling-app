package com.lumin.app

import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Prompt 15 — entry point for high-priority FCM data messages.
 *
 * The system invokes onMessageReceived even when our app process is fully
 * dead, so this is the only reliable place to wake the device for an
 * incoming call. We immediately start CallService as a foreground service;
 * CallService does the ringing and shows the full-screen notification.
 *
 * Message types:
 *   incoming_call → start CallService with the call payload
 *   missed_call   → post a missed-call notification
 *   new_message   → ignored (Flutter side handles message notifications)
 */
class FcmService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val type = message.data["type"]
        when (type) {
            "incoming_call" -> handleIncomingCall(message)
            "missed_call" -> handleMissedCall(message)
            "new_message" -> handleNewMessage(message)
            else -> Log.d(TAG, "unhandled FCM type=$type")
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Persist for Flutter to pick up on next launch. We don't ship it
        // synchronously to the server here because the engine may be dead;
        // Flutter reads the latest token from FirebaseMessaging.instance
        // anyway on startup. Storing it for diagnostics / debug only.
        try {
            val prefs: SharedPreferences =
                getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_FCM_TOKEN, token).apply()
        } catch (t: Throwable) {
            Log.w(TAG, "failed to persist token: ${t.message}")
        }
    }

    // ── Handlers ────────────────────────────────────────────────────────────────

    private fun handleIncomingCall(message: RemoteMessage) {
        val data = message.data
        val callId = data["call_id"]
        if (callId.isNullOrBlank()) {
            Log.w(TAG, "incoming_call missing call_id; dropping")
            return
        }

        // ── Foreground guard ────────────────────────────────────────────────
        // FCM `incoming_call` arrives in parallel with the socket
        // `call:incoming` event. When the app is foregrounded, the Flutter
        // IncomingCallScreen already mounted via the socket path and the
        // CallNotifier set up its own dedup. Starting CallService too would:
        //   • double-ring (system ringtone + in-app sounds)
        //   • on Android 14+, fight the in-app UI for audio focus
        //   • risk a 5-second FGS-start-from-background grace violation on
        //     OEMs that enforce it strictly (MIUI/EMUI etc).
        // The socket path is responsible for foreground rings; we only need
        // the native CallService when the app process is killed or fully
        // backgrounded. Skip silently otherwise.
        if (isAppForeground()) {
            Log.i(TAG, "incoming_call: app foregrounded, skipping CallService (Flutter UI handles ring)")
            return
        }

        // Hand the payload to CallService — it'll ring + show the full-screen UI.
        val payload = mapOf(
            CallService.EXTRA_CALL_ID to callId,
            CallService.EXTRA_CALLER_ID to data["caller_id"],
            CallService.EXTRA_CALLER_NAME to (data["caller_name"] ?: "Unknown"),
            CallService.EXTRA_CALLER_AVATAR to data["caller_avatar"],
            CallService.EXTRA_CALL_TYPE to (data["call_type"] ?: "audio"),
            CallService.EXTRA_SDP_OFFER to data["sdp_offer"],
            CallService.EXTRA_SIGNAL_TOKEN to data["signal_token"],
        )
        CallService.startIncoming(this, payload)
    }

    /**
     * True when *this* process has at least one foreground importance
     * component. Uses ActivityManager.RunningAppProcessInfo which is the
     * only API still accessible to non-system apps post-API 26 for this
     * question. Anything other than IMPORTANCE_FOREGROUND we treat as
     * "not visible to the user", which is conservative but correct for
     * this use case (we'd rather over-ring on a backgrounded app than
     * double-ring on a foregrounded one).
     */
    private fun isAppForeground(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return false
            val pid = android.os.Process.myPid()
            val processes = am.runningAppProcesses ?: return false
            processes.any { it.pid == pid &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND }
        } catch (t: Throwable) {
            Log.w(TAG, "isAppForeground check failed: ${t.message}")
            false
        }
    }

    private fun handleNewMessage(message: RemoteMessage) {
        // We register *the* FirebaseMessagingService for the app, which means
        // Flutter's firebase_messaging plugin never sees these messages on
        // its own — so we have to show the notification ourselves when the
        // app is backgrounded or killed. (When the app is foregrounded, the
        // socket delivers the message before this fires, and the Dart side
        // shows its own in-app feedback.)
        // App is open → the in-app UI / socket already shows the message; don't
        // drop a tray notification that we'd then have to clear.
        if (isAppForeground()) return

        ensureMessagesNotificationChannel()
        val data = message.data
        val notification = message.notification

        val title = notification?.title ?: data["sender_name"] ?: "New message"
        val body = notification?.body ?: data["preview"] ?: ""
        val conversationId = data["conversation_id"] ?: ""
        val messageId = data["message_id"] ?: ""

        // Tap the notification → open the app on the right conversation.
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
        }
        val tapPending = PendingIntent.getActivity(
            this,
            messageId.hashCode(),
            tapIntent,
            pendingFlags(),
        )

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notif = NotificationCompat.Builder(this, MESSAGES_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setGroup(MESSAGES_GROUP)
            .setContentIntent(tapPending)
            .build()
        // Stable per-conversation id (matches Dart's conversationNotificationId)
        // so a chat's messages collapse into one notification AND Flutter can
        // cancel it when the chat is opened/read.
        val notifId = if (conversationId.isNotEmpty()) {
            convNotifId(conversationId)
        } else {
            messageId.hashCode().takeIf { it != 0 } ?: 1
        }
        nm.notify(notifId, notif)
        postMessagesSummary(nm)
    }

    /**
     * Group-summary notification so multiple chats bundle under one
     * "New messages" header instead of stacking loose. Re-posting with the
     * same id refreshes it; Android removes it once its last child is cleared.
     */
    private fun postMessagesSummary(nm: NotificationManager) {
        val count = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            nm.activeNotifications.count {
                it.notification.group == MESSAGES_GROUP &&
                    it.id != MESSAGES_SUMMARY_ID
            }
        } else {
            0
        }
        val text = if (count > 1) "$count conversations" else "New messages"
        val summary = NotificationCompat.Builder(this, MESSAGES_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notification)
            .setContentTitle("New messages")
            .setContentText(text)
            .setStyle(NotificationCompat.InboxStyle().setSummaryText(text))
            .setGroup(MESSAGES_GROUP)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
        nm.notify(MESSAGES_SUMMARY_ID, summary)
    }

    /**
     * 31x polynomial hash masked to 26 bits — kept identical to the Dart
     * `conversationNotificationId` so Flutter can cancel notifications this
     * service posts. (26-bit mask keeps h*31 inside a 32-bit Int.)
     */
    private fun convNotifId(conversationId: String): Int {
        var h = 0
        for (ch in conversationId) {
            h = (h * 31 + ch.code) and 0x3FFFFFF
        }
        return if (h == 0) 1 else h
    }

    private fun ensureMessagesNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(MESSAGES_CHANNEL_ID) != null) return
        val channel = android.app.NotificationChannel(
            MESSAGES_CHANNEL_ID,
            "Messages",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "New message notifications"
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

    private fun handleMissedCall(message: RemoteMessage) {
        val data = message.data
        val callerName = data["caller_name"] ?: "Unknown"
        val callId = data["call_id"] ?: return

        // Tapping the missed-call notification opens the app on call history.
        // MainActivity reads nav_route and routes Flutter to /call/history.
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("nav_route", "/call/history")
        }
        val tapPending = PendingIntent.getActivity(
            this,
            CallService.MISSED_CALL_NOTIFICATION_ID_BASE + callId.hashCode(),
            tapIntent,
            pendingFlags(),
        )

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notif = NotificationCompat.Builder(this, CallService.CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText("From $callerName")
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(tapPending)
            .build()
        nm.notify(
            CallService.MISSED_CALL_NOTIFICATION_ID_BASE + callId.hashCode(),
            notif,
        )
    }

    companion object {
        private const val TAG = "FcmService"
        private const val PREFS = "fcm_prefs"
        private const val KEY_FCM_TOKEN = "fcm_token"
        private const val MESSAGES_CHANNEL_ID = "messages"
        private const val MESSAGES_GROUP = "lumin_messages"
        // Negative so it never collides with a per-conversation convNotifId.
        private const val MESSAGES_SUMMARY_ID = -1000
    }
}
