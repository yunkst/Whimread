import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 强制重建测试数据库
///
/// 此脚本会：
/// 1. 尝试打开并关闭数据库（确保没有残留连接）
/// 2. 删除所有数据库文件
/// 3. 验证删除成功
Future<void> main() async {
  print('=== 强制重建测试数据库 ===\n');

  // 初始化 FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 获取数据库路径
  final databasesPath = await getDatabasesPath();
  print('📂 数据库路径: $databasesPath');

  final dbFile = File('$databasesPath/novel_reader.db');
  final dbShm = File('$databasesPath/novel_reader.db-shm');
  final dbWal = File('$databasesPath/novel_reader.db-wal');

  // 检查文件是否存在
  final files = [dbFile, dbShm, dbWal];
  int existingCount = 0;

  for (final file in files) {
    if (await file.exists()) {
      existingCount++;
      print('   ✓ 找到文件: ${file.path}');
    }
  }

  if (existingCount == 0) {
    print('ℹ️  没有找到数据库文件，无需清理');
    return;
  }

  print('\n🔧 开始清理...');

  // 尝试多次删除（可能有延迟）
  for (int attempt = 1; attempt <= 3; attempt++) {
    print('\n尝试 $attempt/3:');

    int deletedCount = 0;
    for (final file in files) {
      try {
        if (await file.exists()) {
          await file.delete();
          print('   ✓ 已删除: ${file.path}');
          deletedCount++;
        }
      } catch (e) {
        print('   ✗ 删除失败: ${file.path}');
        print('      错误: $e');

        // 如果是文件被占用，等待一下再重试
        if (attempt < 3) {
          print('   ⏳ 等待 2 秒后重试...');
          await Future.delayed(Duration(seconds: 2));
        }
      }
    }

    if (deletedCount == existingCount) {
      print('\n✅ 清理成功！所有文件已删除');
      return;
    }
  }

  print('\n❌ 清理失败：部分文件无法删除');
  print('\n💡 建议：');
  print('   1. 关闭所有运行的测试进程');
  print('   2. 关闭 VS Code 或其他 IDE');
  print('   3. 手动删除文件: $databasesPath');
}
