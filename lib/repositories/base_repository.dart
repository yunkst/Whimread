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
  /// 在 try 中执行 [body]；若抛出异常，记录一条 error 级日志（含异常堆栈），
  /// 然后 rethrow，保证调用方仍能感知原始异常。
  ///
  /// - [opTag]：操作标识；未提供 [message] 时日志消息为
  ///   "Repository $opTag failed"。
  /// - [message]：自定义日志消息构造器，入参为捕获到的异常对象。既有
  ///   "xxx失败: <上下文> - $e" 风格的消息可原样迁入——异常对象只在
  ///   catch 作用域可见，故以回调形式提供。传 null 时使用默认消息。
  /// - [category] / [tags]：日志分类与标签；缺省沿用 database 与
  ///   ['repository', 'guard']（向后兼容旧的两参数签名）。
  ///
  /// 用于消除各 Repository 方法中重复的 try/catch+log+rethrow 样板代码。
  Future<T> guard<T>(
    String opTag,
    Future<T> Function() body, {
    String Function(Object error)? message,
    LogCategory? category,
    List<String>? tags,
  }) async {
    try {
      return await body();
    } catch (e, st) {
      LoggerService.instance.e(
        message != null ? message(e) : 'Repository $opTag failed',
        stackTrace: st.toString(),
        category: category ?? LogCategory.database,
        tags: tags ?? ['repository', 'guard'],
      );
      rethrow;
    }
  }
}
