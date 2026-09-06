# Whimread {{VERSION}}

## 📦 下载说明

本版本按 CPU 架构拆分为多个 APK，请根据设备选择：

| 架构 | 文件 | 适用设备 |
|------|------|----------|
| arm64-v8a | `app-arm64-v8a-release.apk` | 绝大多数现代手机（推荐） |
| armeabi-v7a | `app-armeabi-v7a-release.apk` | 老旧 32 位设备 |
| x86_64 | `app-x86_64-release.apk` | 模拟器 / ChromeOS |

> 💡 在已安装的 App 内「设置 → 检查更新」会自动下载与本机架构匹配的 APK。

## 🔐 完整性校验

下载后用 `SHA256SUMS.txt` 验证文件完整性：

```bash
sha256sum -c SHA256SUMS.txt
```

## 📲 安装步骤

1. 下载对应架构的 APK
2. 在 Android 设备上安装（允许「未知来源」）
3. 首次启动配置后端 API 地址

## 📝 更新日志

<!--CHANGELOG_START-->
{{CHANGELOG}}
<!--CHANGELOG_END-->
