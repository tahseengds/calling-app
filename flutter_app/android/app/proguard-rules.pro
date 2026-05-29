# R8 / ProGuard keep rules for the release build.
# Generous keeps for the native-bridged + reflection-heavy libraries so
# shrinking never strips something invoked via JNI, the manifest, or reflection.

# ── Flutter engine + plugins ────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── WebRTC (heavy JNI + reflection) ─────────────────────────────────────────
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ── flutter_sound recorder/player ───────────────────────────────────────────
-keep class com.dooboolab.** { *; }
-dontwarn com.dooboolab.**

# ── Firebase / Google Play services (FCM, analytics, sign-in) ───────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Our native call layer (referenced by AndroidManifest + method channel) ──
-keep class com.lumin.app.** { *; }

# ── Keep metadata reflection-based libraries rely on ────────────────────────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, RuntimeVisibleAnnotations
-keepclassmembers enum * { *; }
-keep class * implements android.os.Parcelable { *; }

# Desugared library (core library desugaring is enabled).
-dontwarn com.android.tools.**
