package com.lumin.app

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Prompt 15 — Android-native helpers for the battery-optimization /
 * OEM-autostart prompts shown by the Flutter side.
 *
 * Aggressive OEM battery managers (Xiaomi, Huawei, Oppo, Vivo, Samsung) will
 * silently kill the FCM listener and the foreground CallService unless the
 * user explicitly whitelists the app. We can only nudge them — Android has
 * no public API to grant the whitelist programmatically.
 */
object BatteryOptimization {

    fun isIgnoring(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    /**
     * Open the per-app battery-optimization settings screen. We deliberately
     * do NOT use ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (the
     * single-tap whitelist intent) because Google Play disallows it for
     * most app categories; the settings screen is the safe variant.
     */
    fun requestIgnore(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            activity.startActivity(intent)
        } catch (_: Throwable) {
            openAppSettings(activity)
        }
    }

    fun openAppSettings(ctx: Context) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", ctx.packageName, null)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            ctx.startActivity(intent)
        } catch (_: Throwable) { /* nothing else we can do */ }
    }

    /**
     * Returns a small map Flutter uses to show OEM-specific tips:
     *   manufacturer, model, isAggressive, autoStartLabel
     */
    fun getOemHints(): Map<String, Any?> {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val isAggressive = AGGRESSIVE_OEMS.contains(manufacturer)
        val autoStartLabel = when (manufacturer) {
            "xiaomi", "redmi", "poco" -> "Security → Permissions → Autostart"
            "huawei", "honor" -> "Phone Manager → Protected apps"
            "oppo", "realme" -> "Settings → Battery → App energy saver"
            "vivo" -> "Settings → Battery → High background power consumption"
            "samsung" -> "Settings → Apps → Lumin → Battery → Unrestricted"
            else -> null
        }
        return mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "model" to (Build.MODEL ?: ""),
            "isAggressive" to isAggressive,
            "autoStartLabel" to autoStartLabel,
        )
    }

    /**
     * Try to deep-link into the OEM-specific autostart / background-activity
     * screen. Returns false if we couldn't find a known intent for this
     * manufacturer — Flutter should then fall back to plain app settings.
     */
    fun openOemAutoStartSettings(activity: Activity): Boolean {
        val candidates = oemAutoStartIntents()
        for (c in candidates) {
            try {
                activity.startActivity(c)
                return true
            } catch (_: Throwable) { /* try the next */ }
        }
        return false
    }

    private fun oemAutoStartIntents(): List<Intent> {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        return when (manufacturer) {
            "xiaomi", "redmi", "poco" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    ),
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            )
            "huawei", "honor" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    ),
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
                Intent().setComponent(
                    ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity",
                    ),
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            )
            "oppo", "realme" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                    ),
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            )
            "vivo" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    ),
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            )
            else -> emptyList()
        }
    }

    private val AGGRESSIVE_OEMS = setOf(
        "xiaomi", "redmi", "poco",
        "huawei", "honor",
        "oppo", "realme",
        "vivo",
        "samsung",
    )
}
