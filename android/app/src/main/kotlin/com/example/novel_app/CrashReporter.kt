package com.example.novel_app

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native crash 报告器。
 *
 * 分工：
 * - [install]：在 MainActivity.onCreate 最早期调用，通过 [nativeInstall]
 *   注册 NDK signal handler（SIGSEGV/SIGABRT/SIGBUS/SIGILL/SIGFPE/SIGTRAP）。
 *   handler 在进程被 kill 前把崩溃信息写到 filesDir/crash/crash_*.txt。
 * - [registerChannel]：暴露 `com.example.novel_app/crash` MethodChannel 给
 *   Flutter 侧，读取 / 删除 dump 文件，供下次启动弹框展示。
 *
 * 设计：C handler 只负责"进程死亡前写文件"（受 async-signal-safe 约束）；
 * 读 / 删 / 解析都在 Kotlin/Dart 侧（无此约束）。
 *
 * 加载失败容错：loadLibrary / nativeInstall 失败只记录日志，不抛异常——
 * 即便没有 native crash 捕获，app 也应能正常启动。
 */
object CrashReporter {
    private const val TAG = "CrashReporter"
    private const val CHANNEL = "com.example.novel_app/crash"
    private const val CRASH_DIR = "crash"

    init {
        try {
            System.loadLibrary("crash_handler")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "loadLibrary crash_handler failed", e)
        }
    }

    /**
     * NDK signal handler 安装入口（由 cpp/crash_handler.c 实现）。
     *
     * JNI 命名：包名 com.example.novel_app 的下划线按规则编码为 _1。
     */
    @JvmStatic
    external fun nativeInstall(dumpDir: String)

    /**
     * 注册 NDK signal handler。dump 目录：filesDir/crash/。
     * 必须在 app 启动最早期（MainActivity.onCreate super 之后）调用。
     */
    fun install(context: Context) {
        val dir = File(context.filesDir, CRASH_DIR)
        if (!dir.exists()) dir.mkdirs()
        try {
            nativeInstall(dir.absolutePath)
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "nativeInstall failed (lib not loaded)", e)
        }
    }

    /**
     * 注册 MethodChannel，供 Flutter 侧读取 / 删除 dump。
     */
    fun registerChannel(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkDumps" -> result.success(readDumps(context))
                "deleteDumps" -> {
                    deleteDumps(context)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 读取所有 dump 文件（按修改时间升序，最早崩溃在前）。 */
    private fun readDumps(context: Context): List<Map<String, String>> {
        val dir = File(context.filesDir, CRASH_DIR)
        val files = dir.listFiles()?.filter { it.isFile && it.name.endsWith(".txt") }
            ?: return emptyList()
        return files.sortedBy { it.lastModified() }.map { f ->
            mapOf(
                "fileName" to f.name,
                "content" to runCatching { f.readText() }.getOrDefault("(读取失败)"),
            )
        }
    }

    private fun deleteDumps(context: Context) {
        val dir = File(context.filesDir, CRASH_DIR)
        dir.listFiles()?.forEach { it.delete() }
    }
}
