plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.lumin.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications and other packages that use
        // newer Java time/stream APIs on Android < 26.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.lumin.app"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // R8 code shrink + obfuscation and unused-resource stripping.
            // Cuts dex + resources out of the release build; native .so size is
            // handled separately by per-ABI splits / app bundle.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:34.13.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    // Required by FcmService.kt (prompt 15) — Android-native FirebaseMessagingService.
    // firebase_messaging Flutter plugin already pulls this transitively, but we
    // depend on it explicitly so the symbol resolves during Kotlin compilation
    // even if the plugin's transitive deps change.
    implementation("com.google.firebase:firebase-messaging")
    // AndroidX core / notifications used by CallService.
    implementation("androidx.core:core-ktx:1.13.1")
}
