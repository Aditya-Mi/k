plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.adityamittal.k"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (scheduled reminders) needs desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.adityamittal.k"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // CI signs releases with the key from repo secrets (K_KEYSTORE etc.). It is
    // the same key the phone's install was signed with, so updates install
    // over it and Google sign-in (matched by SHA-1) keeps working. Local
    // release builds fall back to the debug key.
    val ciKeystore = System.getenv("K_KEYSTORE")
    signingConfigs {
        if (ciKeystore != null) {
            create("ci") {
                storeFile = file(ciKeystore)
                storePassword = System.getenv("K_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("K_KEY_ALIAS")
                keyPassword = System.getenv("K_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (ciKeystore != null) "ci" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
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

dependencies {
    // Expedited background processing of incoming bank SMS (headless Flutter engine).
    implementation("androidx.work:work-runtime-ktx:2.10.5")
    // FileProvider: hands a downloaded update APK to the installer.
    implementation("androidx.core:core-ktx:1.13.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
