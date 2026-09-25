import java.util.Base64
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val nextDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(",")
    .filter { it.isNotBlank() }.mapNotNull {
        val pair = String(Base64.getDecoder().decode(it)).split("=", limit = 2)
        if (pair.size == 2) pair[0] to pair[1] else null
    }.toMap()

// Keep the independent Next test identity stable across machines. Never fall
// back to a newly generated global debug key, which cannot update the S24 app.
val nextDebugKeystore = System.getenv("VORTICE_NEXT_DEBUG_KEYSTORE")
    ?.takeIf { it.isNotBlank() }?.let { file(it) }
    ?: rootProject.file("../config/vortice-next-debug.keystore")
val nextDebugCertificateSha256 = "bff1c47390f744b8143ddb53762d7a63e4a62c2ffe099d27d340ba73da435769"

android {
    namespace = "com.example.vortice_app_next"
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
        applicationId = "com.example.vortice_app_next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Android's background FCM service needs the same explicitly supplied
        // Next options as Dart, including when the Flutter process is closed.
        mapOf("FIREBASE_ANDROID_APP_ID" to "google_app_id", "FIREBASE_API_KEY" to "google_api_key",
            "FIREBASE_MESSAGING_SENDER_ID" to "gcm_defaultSenderId", "FIREBASE_PROJECT_ID" to "project_id")
            .forEach { (key, resource) -> nextDefines[key]?.takeIf { it.isNotBlank() }?.let { resValue("string", resource, it) } }
    }

    signingConfigs {
        getByName("debug") {
            storeFile = nextDebugKeystore
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // No fallback to debug signing. Production identity and protected
            // signing must be deliberately implemented under NEXT-009.
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
        throw GradleException("Production release is not configured. Complete NEXT-009 identity and signing gates; use scripts/build-android.cmd for internal debug builds.")
    }
    if (allTasks.any { it.project == project && it.name.endsWith("Debug") }) {
        if (!nextDebugKeystore.isFile) {
            throw GradleException("Missing independent Next debug key. Restore config/vortice-next-debug.keystore or set VORTICE_NEXT_DEBUG_KEYSTORE; do not generate a replacement.")
        }
        val fingerprint = try {
            val keystore = KeyStore.getInstance(nextDebugKeystore, "android".toCharArray())
            val certificate = keystore.getCertificate("androiddebugkey")
                ?: throw IllegalArgumentException()
            MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        } catch (_: Exception) {
            throw GradleException("Cannot read the independent Next debug signing certificate.")
        }
        if (fingerprint != nextDebugCertificateSha256) {
            throw GradleException("Debug key does not match the established independent Next app. Restore the matching key; do not uninstall the phone app to bypass this check.")
        }
    }
}

flutter {
    source = "../.."
}
