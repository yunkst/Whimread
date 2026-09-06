import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/interfaces/i_database_connection.dart';
import '../services/logger_service.dart';

/// Repository基础类
///
/// 提供数据库访问的通用功能和状态管理
/// 通过依赖注入接受IDatabaseConnection实例
abstract class BaseRepository {
  final IDatabaseConnection _dbConnection;

  /// 构造函数 - 接受数据库连接实例
  BaseRepository({required IDatabaseConnection dbConnection})
      : _dbConnection = dbConnection;

  /// 获取数据库实例（从IDatabaseConnection获取）
  Future<Database> get database => _dbConnection.database;

  /// Web平台检查
  bool get isWebPlatform => kIsWeb;

  /// 统一的错误守护包装器
  ///
  /// 在 try 中执行 [body]；若抛出异常，记录 "Repository $opTag failed" 错误日志
  /// （含异常对象与堆栈），然后 rethrow，保证调用方仍能感知原始异常。
  ///
  /// 用于消除各 Repository 方法中重复的 try/catch+log+rethrow 样板代码。
  Future<T> guard<T>(String opTag, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e, st) {
      LoggerService.instance.e(
        'Repository $opTag failed',
        stackTrace: st.toString(),
        category: LogCategory.database,
        tags: ['repository', 'guard'],
      );
      rethrow;
    }
  }
}
