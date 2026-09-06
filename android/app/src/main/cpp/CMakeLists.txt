cmake_minimum_required(VERSION 3.22.1)
project("novel_crash_handler")

add_library(crash_handler SHARED crash_handler.c)

# _Unwind_Backtrace 来自系统 libgcc_unwind / libc++_shared；
# 在 Android NDK 中由编译器自动链接，无需显式指定 -lunwind。
# log 库仅用于 debug 构建的 __android_log_print（release 不依赖）。
target_link_libraries(crash_handler
    log
)
