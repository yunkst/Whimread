import 'package:sqflite/sqflite.dart';

/// 数据库连接接口
///
/// 定义数据库连接的抽象操作，包括初始化、访问和生命周期管理
abstract class IDatabaseConnection {
  /// 获取数据库实例
  Future<Database> get database;

  /// 初始化数据库连接
  Future<void> initialize();

  /// 关闭数据库连接
  Future<void> close();

  /// 检查数据库是否已初始化
  bool get isInitialized;
}
