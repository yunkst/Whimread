/// ImageModelRepository 单元测试 — 真实内存 SQLite
///
/// 覆盖：
/// - 基本 CRUD（save insert/update 分支、delete、getAll/getById/getByName/getEnabled）
/// - 排序（按 sort_order ASC, id ASC）
/// - 默认值唯一性（setDefault 原子事务）
/// - 名字唯一性（unique 索引触发 ImageModelNameConflictException）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_image_model_repository.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import '../../helpers/test_database_setup.dart' as test_db;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ImageModelRepository repo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    repo = ImageModelRepository(dbConnection: dbConnection);
  });

  tearDown(() async {
    await db.close();
  });

  ImageModel _mk({
    String name = '默认模型',
    String description = '擅长通用场景',
    List<String> tags = const ['通用'],
    ImageModelBackendType backendType = ImageModelBackendType.localSd,
    String filePath = '/data/models/x.gguf',
    int fileSize = 1000,
    int sortOrder = 0,
    bool isDefault = false,
    bool isEnabled = true,
  }) {
    final now = DateTime.now();
    return ImageModel(
      name: name,
      description: description,
      tags: tags,
      backendType: backendType,
      filePath: filePath,
      fileSize: fileSize,
      sortOrder: sortOrder,
      isDefault: isDefault,
      isEnabled: isEnabled,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ============================================================
  // CRUD
  // ============================================================
  group('CRUD', () {
    test('save insert 返回新 id 且字段完整回读', () async {
      final id = await repo.save(_mk(
        name: '古风水墨',
        description: '擅长水墨',
        tags: const ['古风', '水墨'],
        fileSize: 2048,
      ));
      expect(id, isPositive);

      final loaded = await repo.getById(id);
      expect(loaded, isNotNull);
      expect(loaded!.name, '古风水墨');
      expect(loaded.description, '擅长水墨');
      expect(loaded.tags, ['古风', '水墨']);
      expect(loaded.fileSize, 2048);
      expect(loaded.backendType, ImageModelBackendType.localSd);
      expect(loaded.isEnabled, true);
      expect(loaded.isDefault, false);
    });

    test('save update 分支：再次 save 同 id 走 update', () async {
      final id = await repo.save(_mk(name: '旧名'));
      final original = await repo.getById(id);
      final updated = original!.copyWith(
        name: '新名',
        description: '改了',
        tags: const ['标签A'],
      );
      await repo.save(updated);

      final all = await repo.getAll();
      expect(all.length, 1, reason: 'update 不应插入新行');
      expect(all.first.name, '新名');
      expect(all.first.description, '改了');
      expect(all.first.tags, ['标签A']);
    });

    test('delete 真正删行', () async {
      final id = await repo.save(_mk(name: '待删'));
      await repo.delete(id);
      expect(await repo.getById(id), isNull);
    });

    test('getAll 按 sort_order ASC, id ASC 排序', () async {
      await repo.save(_mk(name: 'B', sortOrder: 2));
      await repo.save(_mk(name: 'A', sortOrder: 1));
      await repo.save(_mk(name: 'C', sortOrder: 3));
      await repo.save(_mk(name: 'A2', sortOrder: 1));
      final names = (await repo.getAll()).map((m) => m.name).toList();
      expect(names, ['A', 'A2', 'B', 'C'],
          reason: 'sort_order=1 内 id 升序，sort_order=1+ 升序');
    });

    test('getEnabled 只返回启用项', () async {
      await repo.save(_mk(name: '启用', isEnabled: true));
      await repo.save(_mk(name: '停用', isEnabled: false));
      final names = (await repo.getEnabled()).map((m) => m.name).toList();
      expect(names, ['启用']);
    });

    test('getByName 区分大小写精确匹配', () async {
      await repo.save(_mk(name: 'Foo'));
      expect((await repo.getByName('Foo')), isNotNull);
      expect(await repo.getByName('foo'), isNull);
    });

    test('getNextSortOrder 累加 1', () async {
      final first = await repo.getNextSortOrder();
      await repo.save(_mk(name: 'a', sortOrder: first));
      final second = await repo.getNextSortOrder();
      expect(second, first + 1);
    });
  });

  // ============================================================
  // 唯一性约束
  // ============================================================
  group('唯一性约束', () {
    test('setDefault 原子事务：旧默认被清掉，新默认生效，且无多默认', () async {
      final idA = await repo.save(_mk(name: 'A', isDefault: true));
      final idB = await repo.save(_mk(name: 'B'));
      await repo.setDefault(idB);

      final a = await repo.getById(idA);
      final b = await repo.getById(idB);
      expect(a!.isDefault, false);
      expect(b!.isDefault, true);
      expect((await repo.getAll()).where((m) => m.isDefault).length, 1);
    });

    test('save 时 name 重复 → 抛 ImageModelNameConflictException', () async {
      await repo.save(_mk(name: '唯一'));
      expect(
        () => repo.save(_mk(name: '唯一')),
        throwsA(isA<ImageModelNameConflictException>()),
      );
    });

    test('编辑自身时 update name 不触发冲突（unique 索引允许）', () async {
      // sqlite UNIQUE 索引在 UPDATE 不修改索引列时不触发；测试者不修改 name 即可
      final id = await repo.save(_mk(name: '保留', description: '原'));
      await repo.save((await repo.getById(id))!.copyWith(description: '新'));
      expect((await repo.getById(id))!.description, '新');
    });
  });

  // ============================================================
  // JSON tags 序列化
  // ============================================================
  group('tags JSON 序列化', () {
    test('空 tags 落库后读出为空列表', () async {
      final id = await repo.save(_mk(name: '空标签', tags: const []));
      expect((await repo.getById(id))!.tags, isEmpty);
    });

    test('含特殊字符的 tags 正确编解码', () async {
      final id = await repo.save(_mk(
        name: '特殊',
        tags: const ['包含"引号', '换行\n符', '中文 / 英文 mix'],
      ));
      final loaded = (await repo.getById(id))!;
      expect(loaded.tags, ['包含"引号', '换行\n符', '中文 / 英文 mix']);
    });
  });
}