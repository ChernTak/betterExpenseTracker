plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.expense_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.expense_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // vosk_flutter_2 (FR4.4 hands-free wake word) declares minSdkVersion
        // 30 itself, which would otherwise force the whole app's floor up
        // to Android 11 via the manifest merge. AndroidManifest.xml's
        // tools:overrideLibrary tells the merger to trust this app's own
        // (lower) minSdk instead — WakeWordService then gates itself off at
        // runtime below API 30 (device_info_plus SDK_INT check) rather than
        // risking an unverified native call into code the plugin never
        // claimed to support there. Tap-to-talk voice (speech_to_text) has
        // no such floor and works down to whatever minSdk is set here.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // GeofencingClient for the high-spend-area nudge (GeofenceManager.kt) —
    // not something the geolocator plugin exposes to app-level Kotlin code,
    // so it's declared directly here.
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
