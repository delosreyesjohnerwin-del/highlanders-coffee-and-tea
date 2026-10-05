plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json and generates the string resources
    // Firebase.initializeApp() reads on Android. Applied after the Flutter plugin
    // so the generated resources land before the app module is evaluated.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.highlanderscoffee.highlanders_coffee"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by firebase_auth: it uses java.time and other java.* APIs that
        // are unavailable on older Android runtimes. Without this the app fails to
        // build the moment the Firebase plugin is applied.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.highlanderscoffee.highlanders_coffee"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Backs isCoreLibraryDesugaringEnabled above. The version is pinned to the
    // one the Firebase Android SDK expects; letting it float risks a mismatch
    // that only shows up as a runtime crash.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
