plugins {
    id("com.android.application")
}

android {
    namespace = "com.misitioweb.miapk"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.misitioweb.miapk"
        minSdk = 26
        targetSdk = 35
        versionCode = 11
        versionName = "0.4.2"
    }

    signingConfigs {
        create("miapk") {
            // Clave fija para que cada versión nueva se instale encima de la anterior.
            storeFile = file("miapk-v01.keystore")
            storePassword = "miapk-v01"
            keyAlias = "miapk"
            keyPassword = "miapk-v01"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("miapk")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
