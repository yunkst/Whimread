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

    // 2026-09 APK 瘦身：libsds.so（stable-diffusion 引擎，arm64 约 57MB）改为
    // 启动资源引导动态下载（lib/services/app_resource_manager.dart），不再打进 APK。
    // CMake 仍会编出 so（供 tool/publish_resources.dart 收集上传到资源 bucket），
    // 这里只从打包产物中排除。
    //
    // Local Dream 嵌入式引擎（libstable_diffusion_core.so，2026-09）例外：
    // 它不是被 dlopen 的库而是被 spawn 的可执行文件，Android 10+ W^X 禁止
    // exec 私有目录文件，必须经 installer 解包到 nativeLibraryDir——因此
    // 1) 不能像 libsds.so 一样动态下载；2) 必须 useLegacyPackaging=true
    // （否则 so 不解压、直接从 APK 内映射，nativeLibraryDir 下没有文件可执行）。
    // 产物放置：Local Dream build.sh 产出 → android/app/src/main/jniLibs/arm64-v8a/
    packagingOptions {
        jniLibs {
            excludes += "**/libsds.so"
            useLegacyPackaging = true
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
