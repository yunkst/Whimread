# Flutter OnnxRuntime proguard 规则
#
# 背景：release 构建默认开 R8 shrinking/obfuscation，会混淆/裁剪 onnxruntime 的
# Java 桥接类。libonnxruntime4j_jni.so 的 native 代码通过 JNI 按原名反射调用
# ai.onnxruntime.* 的 Java 类与方法（FindClass / GetMethodID），R8 把这些类名
# 混淆成 b.a 后，native 反射失败 -> SIGABRT（vivo Android 16 真机 100% 必崩）。
#
# 现象：debug 不崩（不开 R8）、release 必崩、模拟器不崩（x86 R8 结果不同）。
# 日志停在 "OCR ONNX 推理开始"，因为崩溃发生在 session.run() 调进 native 后
# 的 JNI 查找阶段，Dart try/catch 接不住 native abort。
#
# 修复：keep 住所有被 native 反射调用的类。

# ONNX Runtime 官方 Java API（libonnxruntime4j_jni.so 反射调用）
-keep class ai.onnxruntime.** { *; }

# flutter_onnxruntime 插件（Dart <-> Java 桥接，Plugin 注册被反射调用）
-keep class com.masicai.flutteronnxruntime.** { *; }
