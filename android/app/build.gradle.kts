import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取签名配置（key.properties 不进 git，本地与 CI 各自生成）
// 文件不存在时（如未签名的 debug 构建）会优雅降级到 debug 签名
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        load(FileInputStream(keystoreFile))
    }
}

android {
    namespace = "com.example.novel_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.novel_app"
        // You can update the following values to match your application needs.
        // For more information, go to: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // PP-OCRv6: 禁止压缩 .onnx，避免运行时加载过慢/失败。
    // 注意：不要在这里设 ndk.abiFilters，会与 CI 的 flutter build apk --split-per-abi
    // 冲突（splits abi filters 与全局 ndk abiFilters 不能同时存在）。ABI 控制交给
    // splits/release config；开发者本机用 flutter build apk --release（非 split），
    // 模拟器需要 x86_64 可临时切到 debug 模式跑。
    androidResources {
        noCompress += listOf("onnx")
    }

    // Native crash handler：CMake 编译 libcrash_handler.so（ARM64 / ARMv7 / x86_64）。
    // 不设 ndk.abiFilters，与 CI --split-per-abi 无冲突；CMake 默认编译所有目标 ABI。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        create("release") {
            // 仅当 key.properties 存在且字段完整时启用，否则降级为 debug 签名
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            // storeFile 用 rootProject.file 解析，相对于 android 根目录（避免 app/app/ 双重路径）
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { rootProject.file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // 当 key.properties 不存在（如本地无签名配置）时，
            // release 签名为空，会自动回退到 debug 签名，保证 `flutter run --release` 仍可用。
            val hasKeystore = rootProject.file("key.properties").exists()
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
