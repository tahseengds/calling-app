# Android Calling — Manual Test Matrix (Prompt 15)

The native call layer (`CallService`, `FcmService`, `CallActionReceiver`,
`MainActivity` MethodChannel bridge) is the part of FamilyLink that cannot be
unit-tested meaningfully. This document is the manual checklist a release
build must clear on real hardware before shipping.

> The OS behaviours that gate this feature (Doze, BAL restrictions, OEM
> autostart killers, foreground-service start-time limit) only fire under
> conditions the emulator does not reproduce. **Do every row on a physical
> device.**

## Devices

| Device | Role | Why |
|---|---|---|
| Pixel 7 (Android 14 stock) | baseline | clean reference behaviour |
| Samsung Galaxy A-series (One UI 6+) | aggressive | most aggressive battery management; tests the OEM-autostart card |
| Xiaomi (HyperOS / MIUI 14) | aggressive | second-most aggressive; separate autostart flag |
| (optional) Huawei / Oppo / Vivo | nice-to-have | OEM coverage |

## Pre-flight on each device

1. Install a release-mode APK (`flutter build apk --release` + `adb install`).
   Debug builds skip several OS battery checks.
2. Sign in as user A. Have user B on a separate device or simulator.
3. Open **Profile → Reliable calls** card and follow the prompt for this
   device (allow background activity, enable autostart on aggressive OEMs).
4. Confirm `adb shell dumpsys notification | grep calls` shows the `calls`
   notification channel with importance HIGH.

## Test matrix

Each row should be tested **audio** and **video** unless noted.

| # | App state | Screen | Action | Expected |
|---|-----------|--------|--------|----------|
| 1 | foregrounded, on call list | on | B calls A | one ring; in-app incoming UI; FCM/socket de-duped (no double-ring) |
| 2 | backgrounded (home button) | on | B calls A | full-screen incoming notification within ~2 s; heads-up if device unlocked |
| 3 | fully killed (`adb shell am force-stop com.lumin.app`) | on | B calls A | full-screen incoming notification within ~3–5 s; ringtone + vibration |
| 4 | fully killed | **off** (locked) | B calls A | screen turns on, full-screen call UI over the keyguard, ringtone plays |
| 5 | row 4 → Accept on lock screen | locked | tap Accept on full-screen | MainActivity opens over keyguard, WebRTC connects, audio/video flows |
| 6 | row 4 → Decline from notification | locked | tap Decline | ringtone stops immediately, caller sees `rejected` |
| 7 | row 3 → ignore the call | on | wait 45 s | ringtone stops, missed-call notification visible, server `call_records.status = missed` |
| 8 | in-call (connected) | on | press hardware power → wait 30 s → press power | call still connected, no ICE failure (network stayed up) |
| 9 | in-call (connected) | on | toggle wifi off then back on | brief reconnecting overlay, then connected (ICE restart) |
| 10 | in-call A | on | C calls A | C sees `busy`; A's call is undisturbed |
| 11 | Samsung specifically | off (locked, Doze) | wait 30 min in Doze, B calls A | call still rings within ~5 s (FCM high-priority should escape Doze) |
| 12 | Samsung specifically, with the **Reliable calls** card showing | on | tap "Open auto-start" | system opens **Settings → Apps → Lumin → Battery → Unrestricted** (or the OEM-specific equivalent) |
| 13 | Battery-optimization off (default) | on | open Profile | "Reliable calls" card visible, button reads "Allow background" |
| 14 | Battery-optimization on (whitelisted) | on | open Profile | card hidden (or, on aggressive OEM, reads "Open auto-start") |

## Server-side checks for each test

Where the row touches the backend, also verify:

- Row 5 (Accept on lock screen): `call_records` row exists with `status=completed`, `started_at` ≈ test time, `duration_seconds > 0`.
- Row 6 (Decline from notification): `call_records.status=rejected`, `duration_seconds=null`.
- Row 7 (Ignore until timeout): `call_records.status=missed`.

## Known caveats

- **MIUI / HyperOS**: even after enabling Autostart, MIUI can kill background
  services if the user "force-closes" via the recents tray. Document this in
  the in-app onboarding copy.
- **Samsung "Deep Sleep" apps list**: the auto-start intent we open is
  *Battery → Unrestricted*. The user must additionally **remove Lumin from
  Deep Sleep** if they once put it there. There is no direct intent for that
  list — we surface it as instructional text in the OEM hint string.
- **Android 14 BAL restrictions**: starting MainActivity from
  `CallActionReceiver` (cold-launch on decline/accept) requires the
  `FullScreenIntent` permission on the *notification*, not the *activity* —
  we satisfy this by always presenting via `setFullScreenIntent(...)` first.

## How to triage a failure

1. `adb logcat -v threadtime | grep -iE 'fcm|callservice|callaction|lumin'`
2. `adb shell dumpsys notification --noredact | grep -i calls -A 20`
3. `adb shell dumpsys deviceidle` to confirm Doze isn't holding the FCM.
4. Confirm FCM token registered on the server (`fcm_tokens` table for user A).
5. Re-run with `flutter build apk --release --verbose` to surface
   ProGuard/R8 stripping if the service classes disappear.
