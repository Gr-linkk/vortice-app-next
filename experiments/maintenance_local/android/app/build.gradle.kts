plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.vortice.next.maintenance_local"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.vortice.next.maintenance_local"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Lab artifacts are debug builds; production signing is not configured.
            signingConfig = null
        }
    }
    signingConfigs.getByName("debug") {
        // Dedicated internal lab identity; never reuse the application's signer.
        storeFile = System.getenv("VORTICE_MAINTENANCE_KEYSTORE")?.let { file(it) }
        storePassword = "android"
        keyAlias = "sync-lab-debug"
        keyPassword = "android"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
        throw GradleException("Local Maintenance supports internal debug builds only.")
    }
}
