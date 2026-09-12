cmake_minimum_required(VERSION 3.22.1)
project("novel_crash_handler")

add_library(crash_handler SHARED crash_handler.c)

# _Unwind_Backtrace 来自系统 libgcc_unwind / libc++_shared；
# 在 Android NDK 中由编译器自动链接，无需显式指定 -lunwind。
# log 库仅用于 debug 构建的 __android_log_print（release 不依赖）。
target_link_libraries(crash_handler
    log
)

# ============================================================
# sd.cpp 本地生图引擎（阶段 B）
#
# - 仅在 arm64-v8a 下编译：SD1.5/SDXL 量化推理内存压力大，32 位（armv7）
#   地址空间不够，x86_64 模拟器无实际生图场景；其余 ABI 只带 crash_handler。
#   Dart 侧 LocalSdCppBackend.isEngineBinaryAvailable 探测不到 libsds.so
#   时会优雅降级为 engine_not_ready。
# - 关闭 WebP/WebM/GPU 后端：纯 CPU(NEON) 推理，产物最小化。
# - OUTPUT_NAME=sds → 产出 libsds.so，与
#   lib/services/image_generation/local_sd_backend.dart 的 engineBinaryName 对齐。
# ============================================================
if(ANDROID AND ANDROID_ABI STREQUAL "arm64-v8a")
    set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SD_WEBP OFF CACHE BOOL "" FORCE)
    set(SD_WEBM OFF CACHE BOOL "" FORCE)
    set(SD_BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
    set(SD_USE_SYSTEM_GGML OFF CACHE BOOL "" FORCE)

    add_subdirectory(sd.cpp)

    # gradle 的 splits abi 目录结构要求 .so 位于 jni/<abi>/；OUTPUT_NAME
    # 只改文件名，不改目标名，Dart FFI 与 Kotlin 侧都按 libsds.so 引用。
    set_target_properties(stable-diffusion PROPERTIES OUTPUT_NAME "sds")
endif()
