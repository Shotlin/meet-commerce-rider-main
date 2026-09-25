plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.meetcommerce.rider"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs
        // that need core-library desugaring on minSdk < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.meetcommerce.rider"
        // Geolocator + flutter_secure_storage require API 23+.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Three flavors. Dev/staging currently point at the same Meet Commerce
    // backend host as prod unless API_BASE_URL/SOCKET_BASE_URL are overridden
    // with --dart-define (see lib/core/config/env.dart).
    // Flavors differ in app id suffix, app name, and a BuildConfig flag the
    // Dart side can read via --dart-define=FLAVOR=...
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Freashcut Rider Dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Freashcut Rider Staging")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Freashcut Rider")
        }
    }

    buildTypes {
        release {
            // Debug-signed for now so `flutter run --release` works during development.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring runtime, required by
    // flutter_local_notifications. Version pinned per the package's
    // android docs (>= 2.1.4 for AGP 8 + JDK 17).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
