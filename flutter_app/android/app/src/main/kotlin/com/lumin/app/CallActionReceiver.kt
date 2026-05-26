package com.lumin.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Prompt 15 — handles Accept / Decline taps on the foreground call notification.
 *
 * Two paths depending on whether the Flutter engine is alive:
 *   • Alive  → forward via NativeCallBus to CallNotifier; CallService is then
 *              told to stop by Flutter once it has actually accepted/declined.
 *   • Dead   → launch MainActivity with native_action=accept|decline + the call
 *              payload as extras; MainActivity stashes them and Flutter pulls
 *              them on startup via getInitialCallData().
 *
 * In both cases we stop the ringtone immediately by stopping the service so the
 * device goes quiet the moment the user taps the action.
 */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val callId = intent.getStringExtra(CallService.EXTRA_CALL_ID) ?: return

        val nativeAction = when (action) {
            ACTION_ACCEPT -> "accept"
            ACTION_DECLINE -> "decline"
            else -> return
        }

        // Build the payload map so Flutter (alive or cold-starting) gets the
        // full original call data, not just the action.
        val payload = HashMap<String, Any?>().apply {
            for (key in CallService.PAYLOAD_KEYS) {
                val v = intent.getStringExtra(key)
                if (v != null) this[key] = v
            }
            put(CallService.EXTRA_NATIVE_ACTION, nativeAction)
        }

        if (NativeCallBus.isEngineAlive()) {
            // Engine is alive — push the event; CallNotifier will resolve it.
            NativeCallBus.invoke("callAction", payload)
            // Decline can stop ringing immediately. For accept we leave the
            // service running until Flutter has actually answered (it'll call
            // stopCallService).
            if (nativeAction == "decline") {
                CallService.stopForCallId(context, callId)
            }
        } else {
            // Engine dead — launch MainActivity to bring the app forward.
            val launch = Intent(context, MainActivity::class.java).apply {
                this.action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(CallService.EXTRA_FROM_CALL_NOTIFICATION, true)
                putExtra(CallService.EXTRA_NATIVE_ACTION, nativeAction)
                for (key in CallService.PAYLOAD_KEYS) {
                    val v = intent.getStringExtra(key)
                    if (v != null) putExtra(key, v)
                }
            }
            context.startActivity(launch)
            // Decline: stop the service right away. Accept: let it stop after
            // Flutter has wired up the answer.
            if (nativeAction == "decline") {
                CallService.stopForCallId(context, callId)
            }
        }
    }

    companion object {
        const val ACTION_ACCEPT = "com.lumin.app.action.CALL_ACCEPT"
        const val ACTION_DECLINE = "com.lumin.app.action.CALL_DECLINE"
    }
}
