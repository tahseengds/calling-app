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

        // ACTION_HANGUP fires from the ActiveCallService notification while
        // an answered call is in progress. There's no ringing service to
        // stop and no incoming-call payload to forward — just tell Flutter
        // to end the call, then stop the active-call foreground service.
        if (action == ACTION_HANGUP) {
            val payload = HashMap<String, Any?>().apply {
                put(CallService.EXTRA_CALL_ID, callId)
                put(CallService.EXTRA_NATIVE_ACTION, "hangup")
            }
            if (NativeCallBus.isEngineAlive()) {
                NativeCallBus.invoke("callAction", payload)
            } else {
                // Engine dead — launch MainActivity so the user can see the
                // (now ended) call screen. Flutter's bootstrap will pull
                // native_action=hangup via getInitialCallData() and end the
                // call immediately on startup.
                val launch = Intent(context, MainActivity::class.java).apply {
                    this.action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(CallService.EXTRA_FROM_CALL_NOTIFICATION, true)
                    putExtra(CallService.EXTRA_NATIVE_ACTION, "hangup")
                    putExtra(CallService.EXTRA_CALL_ID, callId)
                }
                context.startActivity(launch)
            }
            ActiveCallService.stop(context)
            return
        }

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

        val engineAlive = NativeCallBus.isEngineAlive()

        // ── Bring the app forward on ACCEPT ──────────────────────────────────
        // A notification ACTION button does NOT open the app on its own (unlike
        // tapping the notification body). So when the user accepts, the call
        // would connect with the app still in the background and no call screen
        // — they'd have no idea they were in a call until they manually opened
        // the app. Launch MainActivity ourselves so it comes to the foreground
        // and routes to the call screen. We do this whether the engine is alive
        // or dead. Decline never opens the app; it only needs the cold-start
        // launch (engine dead) so Flutter can record the rejection.
        if (nativeAction == "accept" || !engineAlive) {
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
        }

        // If the engine is alive, also forward over the bus for instant
        // processing. For accept this races the launched activity's onNewIntent
        // forward, but CallNotifier.acceptCall is phase-guarded (idempotent), so
        // processing it twice is harmless.
        if (engineAlive) {
            NativeCallBus.invoke("callAction", payload)
        }

        // Decline: stop the ring immediately. Accept: leave the service running
        // until Flutter has actually answered (acceptCall → stopForCallId).
        if (nativeAction == "decline") {
            CallService.stopForCallId(context, callId)
        }
    }

    companion object {
        const val ACTION_ACCEPT = "com.lumin.app.action.CALL_ACCEPT"
        const val ACTION_DECLINE = "com.lumin.app.action.CALL_DECLINE"
        // FIX 7: tapped on the persistent in-call notification's hang-up
        // action while the call is connected.
        const val ACTION_HANGUP = "com.lumin.app.action.CALL_HANGUP"
    }
}
