import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingFile.exists()) signingFile.reader(Charsets.UTF_8).use { signingProperties.load(it) }
val dartDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").filter { it.isNotEmpty() }.associate {
        val pair = String(Base64.getDecoder().decode(it), Charsets.UTF_8).split("=", limit = 2)
        pair[0] to pair.getOrElse(1) { "" }
    }

android {
    namespace = "pe.edu.unp.encargalo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "pe.edu.unp.encargalo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (!dartDefines["FIREBASE_APP_ID"].isNullOrBlank()) {
            resValue("string", "google_app_id", dartDefines.getValue("FIREBASE_APP_ID"))
            resValue("string", "gcm_defaultSenderId", dartDefines.getValue("FIREBASE_SENDER_ID"))
            resValue("string", "google_api_key", dartDefines.getValue("FIREBASE_API_KEY"))
            resValue("string", "project_id", dartDefines.getValue("FIREBASE_PROJECT_ID"))
        }
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("encargaloRelease") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            if (!signingFile.exists()) throw GradleException("Falta firma release. Ejecutar tools/create-signing.ps1; no se usa firma debug para release.")
            signingConfig = signingConfigs.getByName("encargaloRelease")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
