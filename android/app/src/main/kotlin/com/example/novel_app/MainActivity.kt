package com.example.novel_app

import android.os.Build
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val APP_INSTALL_CHANNEL = "com.example.novel_app/app_install"
    private val DEVICE_CHANNEL = "com.example.novel_app/device"
    private val ENGINE_CHANNEL = "com.example.novel_app/engine"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native Crash Channel：供 Flutter 侧读取/删除上次崩溃的 dump 文件。
        CrashReporter.registerChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        // Device Attestation Channel：设备注册（Key Attestation）+ 请求签名
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "attest" -> DeviceAttestation.attest(call, result, this)
                "sign" -> DeviceAttestation.signChallenge(call, result)
                "hasKey" -> result.success(DeviceAttestation.hasKey())
                "androidId" -> result.success(DeviceAttestation.getAndroidId(this))
                else -> result.notImplemented()
            }
        }

        // Local Dream 嵌入式引擎 Channel：Dart 侧 spawn 子进程需要
        // nativeLibraryDir（Android 10+ W^X 只允许执行该目录下的二进制）；
        // prepareQnnLibs 把 assets/local_dream/qnnlibs 解压到私有目录
        // （Flutter rootBundle 无法枚举资产目录，须在 Kotlin 侧 list）。
        // hasQnnLibsAssets 为纯查询（不解压），供状态自检使用。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "hasQnnLibsAssets" -> {
                    try {
                        val names = assets.list("local_dream/qnnlibs")
                        result.success(names != null && names.isNotEmpty())
                    } catch (e: Exception) {
                        // 查询失败与"未打包"（正常回 false）是两种故障：记日志便于区分
                        Log.w("LocalDreamEngine", "hasQnnLibsAssets 查询失败", e)
                        result.success(false)
                    }
                }
                "prepareQnnLibs" -> {
                    // 解压几十至上百 MB 的 QNN 运行库是重 IO，放后台线程执行，
                    // 防首次冷启主线程 ANR；MethodChannel result 须回主线程调用
                    Thread {
                        try {
                            val dir = prepareQnnLibs()
                            runOnUiThread { result.success(dir) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("QNN_PREPARE_FAILED", e.message, null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // App Install Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_INSTALL_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    val success = installApk(filePath)
                    if (success) {
                        result.success(true)
                    } else {
                        result.error("INSTALL_FAILED", "Failed to install APK", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /// 把 assets/local_dream/qnnlibs 下的 QNN 运行库解压到
    /// filesDir/local_dream_runtime，返回运行时目录绝对路径。
    /// 已存在且大小一致的文件跳过（对齐 Local Dream BackendService 逻辑）。
    /// 资产目录为空/缺失时返回空串（由 Dart 侧给出"未打包"引导文案）。
    private fun prepareQnnLibs(): String {
        val runtimeDir = java.io.File(filesDir, "local_dream_runtime")
        if (!runtimeDir.exists()) runtimeDir.mkdirs()
        val names = assets.list("local_dream/qnnlibs") ?: emptyArray()
        if (names.isEmpty()) return ""
        for (name in names) {
            val target = java.io.File(runtimeDir, name)
            // 大小校验启发式：AssetInputStream.available() 在 AOSP 实现里
            // 通常返回整个资产的字节数，但这是实现细节而非 API 契约
            // （个别实现可能返回剩余可读量甚至 0），只能作"是否重拷"的
            // 粗判，不保证与目标文件字节级一致。
            val needsCopy = !target.exists() || run {
                assets.open("local_dream/qnnlibs/$name").use { it.available().toLong() } != target.length()
            }
            if (needsCopy) {
                assets.open("local_dream/qnnlibs/$name").use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
            }
        }
        return runtimeDir.absolutePath
    }

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) {
                return false
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this@MainActivity,
                        "$packageName.fileprovider",
                        file
                    )
                } else {
                    Uri.fromFile(file)
                }
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // ★ 必须在 super.onCreate 之后、任何 Flutter/业务初始化之前注册 NDK signal handler。
        // 尽早注册，最大化覆盖 native crash（包括 flutter_onnxruntime 推理路径）。
        CrashReporter.install(this)

        // 高刷新率：API 23+ 选当前分辨率下刷新率最高的 Display.Mode，告诉系统
        // 该窗口偏好高帧率。否则部分 ROM（含 vivo）默认给 APP 60Hz，体感"卡卡的"。
        // Flutter 自身渲染不受限（引擎按 vsync 出帧），瓶颈在系统给不给 120Hz。
        enableHighRefreshRate()

        // 创建下载任务的通知渠道（Android 8.0+ 需要）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "downloader_notification_channel"
            val channelName = "下载任务"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = "显示APP更新下载进度"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    /// 启用高刷新率：在当前分辨率下选刷新率最高的 Display.Mode。
    ///
    /// 实现方式：遍历 display.supportedModes，匹配当前物理分辨率（避免改分辨率），
    /// 在同分辨率 modes 里挑 refreshRate 最高的，把它的 modeId 设到
    /// window.attributes.preferredDisplayModeId。系统会据此切换该窗口的刷新率。
    ///
    /// 兼容性：API 23+（M）。低于 M 无 Display.Mode API，跳过即可。
    /// 若系统强制 60Hz（如省电模式），本设置被覆盖，不影响功能。
    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = windowManager.defaultDisplay
        val modes = display.supportedModes ?: return
        if (modes.isEmpty()) return
        // 当前物理分辨率（mode.physicalWidth/Height 是各 mode 的物理分辨率）
        val curW = display.mode.physicalWidth
        val curH = display.mode.physicalHeight
        // 在同分辨率下挑刷新率最高的
        var best = display.mode
        for (m in modes) {
            if (m.physicalWidth == curW && m.physicalHeight == curH && m.refreshRate > best.refreshRate) {
                best = m
            }
        }
        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        window.attributes = params
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
