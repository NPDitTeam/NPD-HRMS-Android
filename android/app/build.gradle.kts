import java.util.Properties
import java.io.FileInputStream // เพิ่ม import นี้

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ โหลดค่า MAPS_API_KEY จาก local.properties
val localProperties = Properties().apply {
    val localFile = rootProject.file("local.properties")
    if (localFile.exists()) {
        localFile.inputStream().use { this.load(it) }
    }
}

// ✅ โหลดค่า signing key จาก key.properties
val keyProperties = Properties().apply {
    val keyFile = rootProject.file("key.properties") // key.properties อยู่ใน android/ (rootProject for android module)
    if (keyFile.exists()) {
        keyFile.inputStream().use { this.load(it) }
    }
}

val mapsApiKey: String? = localProperties.getProperty("MAPS_API_KEY")
if (mapsApiKey == null) {
    throw GradleException("❌ Maps API key not found in local.properties. Please add it.")
}

android {
    namespace = "com.npd.npd_hrms_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.npd.npd_hrms_app"
        minSdk = flutter.minSdkVersion  // กำหนดค่าเดิมเพื่อรองรับอุปกรณ์เก่า (Android 5.0+)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey!!
    }

    // *** ส่วนการตั้งค่า SigningConfigs สำหรับ Kotlin DSL (.kts) ***
    signingConfigs {
        create("release") {
            // ดึงค่าจาก keyProperties ที่โหลดไว้ด้านบน
            storeFile = file(keyProperties.getProperty("storeFile"))
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
        }
    }
    // *************************************************************

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
