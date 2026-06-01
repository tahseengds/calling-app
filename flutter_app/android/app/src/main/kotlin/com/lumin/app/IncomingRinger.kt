package com.lumin.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log

/**
 * Process-wide single-instance incoming-call ringer.
 *
 * Why a singleton: an incoming call can be surfaced through more than one path
 * at once — the native [CallService] (app backgrounded / killed) and the
 * Flutter `IncomingCallScreen` (app foregrounded), and sometimes both as the
 * user brings the app forward. Each of those used to start its OWN ringtone
 * (CallService a MediaPlayer, Flutter a synthesized tone via audioplayers),
 * which produced the reported double-ring. Routing every path through this one
 * object guarantees a single ringtone + single vibration: [start] is a no-op
 * while already ringing, so concurrent callers can't stack a second instance.
 *
 * Sound source is the user's selected device ringtone on the
 * USAGE_NOTIFICATION_RINGTONE attributes, so volume follows the device ring
 * volume / silent / vibrate modes — i.e. it behaves like a normal phone call,
 * distinct from the caller-side ringback tone (which is a quiet in-call tone).
 */
object IncomingRinger {
    private const val TAG = "IncomingRinger"

    // Classic ring cadence: short gap, buzz, gap, buzz… repeated (index 0).
    private val VIBRATE_PATTERN = longArrayOf(0, 800, 1000, 800, 1000)

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var ringing = false

    /**
     * Begin ringing + vibrating. Idempotent: if a ring is already in progress
     * this returns immediately, so the foreground and background paths can both
     * call it without ever producing two ringtones.
     */
    @Synchronized
    fun start(context: Context) {
        if (ringing) {
            Log.d(TAG, "start ignored — already ringing")
            return
        }
        ringing = true
        val appContext = context.applicationContext
        // Respect the device ring mode like any phone app: audible ringtone only
        // in NORMAL mode. In VIBRATE mode we vibrate but stay silent; in SILENT
        // mode startVibration() self-gates to nothing. (A raw MediaPlayer does
        // NOT honour the ring mode on its own, unlike the system Ringtone, so we
        // must gate it here — otherwise the phone rings out loud on vibrate.)
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (am?.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            startTone(appContext)
        } else {
            Log.d(TAG, "ringer mode=${am?.ringerMode}; skipping audible tone")
        }
        startVibration(appContext)
    }

    /** Stop + release the ringtone and vibration. Safe to call when idle. */
    @Synchronized
    fun stop() {
        ringing = false
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "stop player failed: ${t.message}")
        }
        player = null
        try {
            vibrator?.cancel()
        } catch (_: Throwable) { /* ignore */ }
        vibrator = null
    }

    private fun startTone(context: Context) {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        // The user's selected ringtone can live in external MediaStore and
        // require READ_MEDIA_AUDIO, which we don't hold — setDataSource then
        // throws SecurityException and the callee hears nothing. Try the user's
        // ringtone first (so an accessible custom/stock ringtone still plays),
        // then fall back through the framework's symbolic default and the
        // notification/alarm defaults (system files under /system/media that
        // always play without storage permission), so the phone always rings.
        val candidates = listOfNotNull(
            runCatching {
                RingtoneManager.getActualDefaultRingtoneUri(
                    context, RingtoneManager.TYPE_RINGTONE,
                )
            }.getOrNull(),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            Settings.System.DEFAULT_RINGTONE_URI,
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            Settings.System.DEFAULT_NOTIFICATION_URI,
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
        ).distinct()

        for (uri in candidates) {
            val mp = tryCreatePlayer(context, uri, attrs)
            if (mp != null) {
                player = mp
                return
            }
        }
        Log.w(TAG, "no playable ringtone URI found; ringing via vibration only")
    }

    /**
     * Build a looping MediaPlayer for [uri], or null if it can't be opened
     * (e.g. SecurityException for a custom ringtone we lack permission for).
     * Always releases the player on failure so we never leak a half-built one.
     */
    private fun tryCreatePlayer(
        context: Context,
        uri: Uri,
        attrs: AudioAttributes,
    ): MediaPlayer? {
        val mp = MediaPlayer()
        return try {
            mp.setAudioAttributes(attrs)
            mp.setDataSource(context, uri)
            mp.isLooping = true
            // Volume rides the device ring stream — don't pin it here.
            mp.prepare()
            mp.start()
            mp
        } catch (t: Throwable) {
            Log.w(TAG, "ringtone uri failed ($uri): ${t.message}")
            try {
                mp.release()
            } catch (_: Throwable) { /* ignore */ }
            null
        }
    }

    private fun startVibration(context: Context) {
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            // Don't buzz when the user has the ringer fully silenced.
            if (am.ringerMode == AudioManager.RINGER_MODE_SILENT) return

            val v: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val mgr =
                    context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                mgr.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = v
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v?.vibrate(VibrationEffect.createWaveform(VIBRATE_PATTERN, 0))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(VIBRATE_PATTERN, 0)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "vibration start failed: ${t.message}")
        }
    }
}
