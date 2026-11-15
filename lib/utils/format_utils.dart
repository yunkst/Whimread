/// 格式化工具类
///
/// 提供常用的数据格式化方法，如文件大小、日期时间等。
/// 统一替代项目中重复的格式化逻辑。
///
/// 使用方式：
/// ```dart
/// // 格式化文件大小
/// final size = FormatUtils.formatFileSize(1024); // "1.0 KB"
/// final size2 = FormatUtils.formatFileSize(1048576); // "1.0 MB"
/// ```
class FormatUtils {
  // 私有构造函数，防止实例化
  FormatUtils._();

  /// 格式化文件大小
  ///
  /// 将字节数转换为人类可读的格式（B, KB, MB, GB, TB）。
  /// [bytes] 文件大小（字节数）
  /// 返回格式化后的字符串，保留1位小数
  ///
  /// 示例：
  /// ```dart
  /// FormatUtils.formatFileSize(0);        // "0 B"
  /// FormatUtils.formatFileSize(500);      // "500 B"
  /// FormatUtils.formatFileSize(1024);     // "1.0 KB"
  /// FormatUtils.formatFileSize(1048576);  // "1.0 MB"
  /// FormatUtils.formatFileSize(1073741824); // "1.0 GB"
  /// ```
  static String formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  /// 紧凑日期时间格式（"YYYY/MM/DD HH:mm"），用于列表/卡片标题等空间受限场景
  ///
  /// 用 `/` 分隔日期、不带秒。
  ///
  /// 示例：
  /// ```dart
  /// FormatUtils.formatDateTimeShort(DateTime(2024, 1, 15, 14, 30));
  /// // "2024/01/15 14:30"
  /// ```
  static String formatDateTimeShort(DateTime dateTime) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} '
        '${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}
