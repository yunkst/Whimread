import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// 统一的偏好设置服务
///
/// 提供类型安全的 SharedPreferences 读写操作，替代重复的代码。
/// 使用单例模式，确保全局唯一实例。
///
/// 所有 set/get 方法均包 try/catch，失败时通过 debugPrint 记录
/// （不能用 LoggerService，因为 LoggerService._persistLogs 依赖本服务，会递归）。
///
/// 使用方式：
/// ```dart
/// // 获取值
/// final value = await PreferencesService.instance.getString('key');
/// final num = await PreferencesService.instance.getInt('number');
///
/// // 设置值
/// await PreferencesService.instance.setString('key', 'value');
/// await PreferencesService.instance.setInt('number', 42);
///
/// // 检查键是否存在
/// final hasKey = await PreferencesService.instance.containsKey('key');
///
/// // 删除键
/// await PreferencesService.instance.remove('key');
///
/// // 清空所有
/// await PreferencesService.instance.clear();
/// ```
class PreferencesService {
  // ========== 单例模式 ==========
  static final PreferencesService _instance = PreferencesService._internal();

  /// 单例实例
  static PreferencesService get instance => _instance;

  factory PreferencesService() => _instance;
  PreferencesService._internal();

  // ========== 公开方法 ==========

  /// 获取字符串值
  ///
  /// 如果键不存在或值为null，返回 [defaultValue]
  Future<String> getString(String key, {String defaultValue = ''}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? defaultValue;
    } catch (e) {
      debugPrint('PreferencesService.getString 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 设置字符串值
  Future<bool> setString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setString(key, value);
    } catch (e) {
      debugPrint('PreferencesService.setString 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 获取整数值
  ///
  /// 如果键不存在或值为null，返回 [defaultValue]
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(key) ?? defaultValue;
    } catch (e) {
      debugPrint('PreferencesService.getInt 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 设置整数值
  Future<bool> setInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setInt(key, value);
    } catch (e) {
      debugPrint('PreferencesService.setInt 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 获取双精度浮点数值
  ///
  /// 如果键不存在或值为null，返回 [defaultValue]
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(key) ?? defaultValue;
    } catch (e) {
      debugPrint('PreferencesService.getDouble 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 设置双精度浮点数值
  Future<bool> setDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setDouble(key, value);
    } catch (e) {
      debugPrint('PreferencesService.setDouble 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 获取布尔值
  ///
  /// 如果键不存在或值为null，返回 [defaultValue]
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? defaultValue;
    } catch (e) {
      debugPrint('PreferencesService.getBool 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 设置布尔值
  Future<bool> setBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setBool(key, value);
    } catch (e) {
      debugPrint('PreferencesService.setBool 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 获取字符串列表值
  ///
  /// 如果键不存在或值为null，返回 [defaultValue]
  Future<List<String>> getStringList(String key,
      {List<String> defaultValue = const []}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(key) ?? defaultValue;
    } catch (e) {
      debugPrint('PreferencesService.getStringList 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 设置字符串列表值
  Future<bool> setStringList(String key, List<String> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setStringList(key, value);
    } catch (e) {
      debugPrint('PreferencesService.setStringList 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 获取底层 SharedPreferences 实例
  ///
  /// 仅供需要直接访问全部键/原始值的场景使用（如备份服务）。
  /// 普通业务请使用上面的 typed get/set 方法。
  Future<SharedPreferences> getInstance() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('PreferencesService.getInstance 失败: $e');
      rethrow;
    }
  }

  /// 检查键是否存在
  Future<bool> containsKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(key);
    } catch (e) {
      debugPrint('PreferencesService.containsKey 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 删除指定键
  Future<bool> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.remove(key);
    } catch (e) {
      debugPrint('PreferencesService.remove 失败: key=$key - $e');
      rethrow;
    }
  }

  /// 清空所有偏好设置
  Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.clear();
    } catch (e) {
      debugPrint('PreferencesService.clear 失败: $e');
      rethrow;
    }
  }

  /// 获取所有键
  Future<Set<String>> getKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getKeys();
    } catch (e) {
      debugPrint('PreferencesService.getKeys 失败: $e');
      rethrow;
    }
  }

  /// 批量设置多个值
  ///
  /// 返回成功设置的键数量
  Future<int> setMultiple(Map<String, dynamic> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int successCount = 0;

      for (final entry in values.entries) {
        bool result = false;
        final value = entry.value;

        if (value is String) {
          result = await prefs.setString(entry.key, value);
        } else if (value is int) {
          result = await prefs.setInt(entry.key, value);
        } else if (value is double) {
          result = await prefs.setDouble(entry.key, value);
        } else if (value is bool) {
          result = await prefs.setBool(entry.key, value);
        } else if (value is List<String>) {
          result = await prefs.setStringList(entry.key, value);
        }

        if (result) successCount++;
      }

      return successCount;
    } catch (e) {
      debugPrint('PreferencesService.setMultiple 失败: $e');
      rethrow;
    }
  }

  /// 批量获取多个值
  ///
  /// 返回键值对映射，不存在的键不会出现在结果中
  Future<Map<String, dynamic>> getMultiple(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = <String, dynamic>{};

      for (final key in keys) {
        final value = prefs.get(key);
        if (value != null) {
          result[key] = value;
        }
      }

      return result;
    } catch (e) {
      debugPrint('PreferencesService.getMultiple 失败: $e');
      rethrow;
    }
  }
}
