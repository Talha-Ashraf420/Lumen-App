import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is loaded from an untracked local file. Google Play App
// Signing should own the distribution key; this is only the upload key.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasKeystore) keystoreProperties.load(FileInputStream(keystorePropertiesFile))
val requiresPlaySigning = gradle.startParameter.taskNames.any {
    it.contains("bundleRelease", ignoreCase = true)
}
val isGooglePlayBuild =
    providers.gradleProperty("googlePlayBuild").orNull.equals("true", ignoreCase = true)
if (requiresPlaySigning && !hasKeystore) {
    throw GradleException(
        "Release app bundles require android/key.properties and a private upload keystore."
    )
}

android {
    namespace = "com.talhaashraf.lumen"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.talhaashraf.lumen"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The Play channel accepts HTTPS providers only. Direct APK builds
        // remain compatible with user-authorized legacy HTTP IPTV services.
        manifestPlaceholders["usesCleartextTraffic"] =
            if (isGooglePlayBuild) "false" else "true"
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Never ship a release artifact signed with Android's public debug key.
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Native Android/TV compatibility engine. Lumen keeps media_kit for its
    // cross-platform player and can hand difficult streams to Media3.
    implementation("androidx.media3:media3-exoplayer:1.10.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.10.0")
    implementation("androidx.media3:media3-ui:1.10.0")
}
