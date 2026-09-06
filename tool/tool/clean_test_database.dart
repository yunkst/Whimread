import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 清理测试数据库工具
///
/// 用于删除测试环境的残留数据库文件
/// 确保每次测试都能使用最新的 Schema
Future<void> cleanTestDatabase() async {
  try {
    // 初始化 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 获取数据库路径
    final databasesPath = await getDatabasesPath();
    final dbFile = '${databasesPath}novel_reader.db';
    final dbShm = '${databasesPath}novel_reader.db-shm';
    final dbWal = '${databasesPath}novel_reader.db-wal';

    print('🔍 正在清理测试数据库...');

    // 删除所有相关文件
    final filesToDelete = [dbFile, dbShm, dbWal];
    int deletedCount = 0;

    for (final file in filesToDelete) {
      try {
        final fileObj = File(file);
        if (await fileObj.exists()) {
          await fileObj.delete();
          deletedCount++;
          print('   ✓ 已删除: $file');
        }
      } catch (e) {
        print('   ✗ 删除失败: $file ($e)');
      }
    }

    if (deletedCount > 0) {
      print('✅ 清理完成，已删除 $deletedCount 个文件');
      print('   下次运行测试时将自动重建数据库（包含最新的 Schema）');
    } else {
      print('ℹ️  没有找到数据库文件，可能已经清理过了');
    }
  } catch (e) {
    print('❌ 清理失败: $e');
    rethrow;
  }
}

/// 检查测试数据库的 Schema
Future<void> checkTestDatabaseSchema() async {
  try {
    // 初始化 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    print('🔍 检查测试数据库 Schema...');

    // 获取数据库路径
    final databasesPath = await getDatabasesPath();
    final dbFile = '${databasesPath}novel_reader.db';
    final fileObj = File(dbFile);

    if (!await fileObj.exists()) {
      print('ℹ️  数据库文件不存在，这是正常的（首次运行时会自动创建）');
      return;
    }

    // 打开数据库检查
    final database = await openDatabase(dbFile, version: 19);

    // 检查 novel_chapters 表结构
    final columns =
        await database.rawQuery('PRAGMA table_info(novel_chapters)');
    final columnNames = columns.map((row) => row['name'] as String).toList();

    print('   当前字段: $columnNames');

    // 检查关键字段
    final requiredColumns = ['readAt', 'isUserInserted', 'isAccompanied'];
    final missingColumns =
        requiredColumns.where((col) => !columnNames.contains(col));

    if (missingColumns.isNotEmpty) {
      print('❌ 缺少字段: ${missingColumns.join(', ')}');
      print('   建议：运行 cleanTestDatabase() 清理旧数据库');
    } else {
      print('✅ 所有必需字段都存在');
    }

    await database.close();
  } catch (e) {
    print('❌ 检查失败: $e');
  }
}

void main() async {
  print('=== 测试数据库清理工具 ===\n');

  print('1️⃣ 检查数据库 Schema...');
  await checkTestDatabaseSchema();

  print('\n2️⃣ 清理旧数据库文件...');
  await cleanTestDatabase();

  print('\n✅ 工具执行完成！');
  print('\n现在可以运行测试了：');
  print('  flutter test test/integration/database_rebuild_test.dart');
}
