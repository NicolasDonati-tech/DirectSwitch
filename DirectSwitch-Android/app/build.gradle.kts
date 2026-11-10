import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.directswitch.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.directswitch.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "1.1.0"
    }

    // Credenziali firma: mai nel codice. Lette da keystore.properties (ignorato da git) oppure da
    // variabili d'ambiente DS_STORE_FILE / DS_STORE_PASSWORD / DS_KEY_ALIAS / DS_KEY_PASSWORD (CI).
    val keystoreProps = Properties().apply {
        val propsFile = rootProject.file("keystore.properties")
        if (propsFile.exists()) propsFile.inputStream().use { load(it) }
    }
    fun signingValue(propKey: String, envKey: String): String? =
        keystoreProps.getProperty(propKey) ?: System.getenv(envKey)
    val releaseStoreFile = signingValue("storeFile", "DS_STORE_FILE")
    val hasReleaseSigning = releaseStoreFile != null &&
        rootProject.file(releaseStoreFile).exists() &&
        signingValue("storePassword", "DS_STORE_PASSWORD") != null

    signingConfigs {
        if (hasReleaseSigning) {
            create("directswitchPermanent") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = signingValue("storePassword", "DS_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "DS_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "DS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            // Stessa firma della release (se disponibile) per permettere aggiornamenti senza disinstallare.
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("directswitchPermanent")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("directswitchPermanent")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.fragment.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.androidx.exifinterface)
    implementation(libs.androidx.documentfile)
    implementation(libs.zxing.core)
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.billing.ktx)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
