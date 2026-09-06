import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../helpers/test_database_setup.dart';

/// SiteScriptRepository.upsertByDomain 单元测试
///
/// 使用真实内存数据库，验证 upsertByDomain 的三个核心分支：
/// - INSERT（首次插入，domain 不存在）
/// - UPDATE（domain 已存在，保留 id/created_at/use_count，重置 verified=0）
/// - 清理重复记录（同 domain 多条记录时保留第一条删除其余）
void main() {
  late SiteScriptRepository repo;
  late Database db;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    repo = SiteScriptRepository(dbConnection: connection);
  });

  tearDown(() async {
    await db.close();
  });

  // ===== 辅助方法 =====

  /// 直接向 site_scripts 表插入一条记录（用于数据准备）
  Future<void> insertRawScript({
    required String id,
    required String domain,
    String chapterListJs = 'const PAGE_URL="{{URL}}"; return JSON.stringify({chapters:[]});',
    String chapterContentJs = 'const PAGE_URL="{{URL}}"; return JSON.stringify({content:""});',
    String urlPattern = '',
    String sampleUrl = '',
    int useCount = 0,
    int verified = 0,
    int? createdAt,
    int? lastUsedAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': id,
      'domain': domain,
      'url_pattern': urlPattern,
      'chapter_list_js': chapterListJs,
      'chapter_content_js': chapterContentJs,
      'sample_url': sampleUrl,
      'created_at': createdAt ?? now,
      'last_used_at': lastUsedAt ?? now,
      'use_count': useCount,
      'verified': verified,
    });
  }

  /// 查询 site_scripts 表中指定 domain 的记录数
  Future<int> countByDomain(String domain) async {
    final results = await db.query(
      'site_scripts',
      where: 'domain = ?',
      whereArgs: [domain],
    );
    return results.length;
  }

  /// 查询 site_scripts 表全部记录数
  Future<int> countAll() async {
    final results = await db.query('site_scripts');
    return results.length;
  }

  // ===== INSERT 分支 =====

  group('upsertByDomain - INSERT（首次插入）', () {
    test('domain 不存在时插入新记录，返回 isInsert=true', () async {
      final result = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'list_script_v1',
        chapterContentJs: 'content_script_v1',
      );

      expect(result.isInsert, isTrue, reason: '首次插入应返回 isInsert=true');
      expect(result.id, isNotEmpty, reason: 'id 应为非空字符串');
    });

    test('插入后数据库中只有一条记录', () async {
      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'list_script_v1',
        chapterContentJs: 'content_script_v1',
      );

      expect(await countByDomain('www.example.com'), 1);
      expect(await countAll(), 1);
    });

    test('插入的记录字段值正确', () async {
      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'list_script_v1',
        chapterContentJs: 'content_script_v1',
        urlPattern: '/chapter/',
        sampleUrl: 'https://www.example.com/novel/1',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved, isNotNull);
      expect(saved!.domain, 'www.example.com');
      expect(saved.chapterListJs, 'list_script_v1');
      expect(saved.chapterContentJs, 'content_script_v1');
      expect(saved.urlPattern, '/chapter/');
      expect(saved.sampleUrl, 'https://www.example.com/novel/1');
      expect(saved.useCount, 0, reason: '首次插入 use_count 应为 0');
      expect(saved.verified, 0, reason: '首次插入 verified 应为 0');
    });

    test('不同 domain 的插入互不影响', () async {
      await repo.upsertByDomain(
        domain: 'www.site-a.com',
        chapterListJs: 'list_a',
        chapterContentJs: 'content_a',
      );
      await repo.upsertByDomain(
        domain: 'www.site-b.com',
        chapterListJs: 'list_b',
        chapterContentJs: 'content_b',
      );

      expect(await countByDomain('www.site-a.com'), 1);
      expect(await countByDomain('www.site-b.com'), 1);
      expect(await countAll(), 2);

      final a = await repo.getByDomain('www.site-a.com');
      expect(a!.chapterListJs, 'list_a');

      final b = await repo.getByDomain('www.site-b.com');
      expect(b!.chapterListJs, 'list_b');
    });
  });

  // ===== UPDATE 分支 =====

  group('upsertByDomain - UPDATE（domain 已存在）', () {
    test('domain 已存在时更新记录，返回 isInsert=false', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        chapterListJs: 'old_list',
        chapterContentJs: 'old_content',
      );

      final result = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      expect(result.isInsert, isFalse, reason: '已存在时应返回 isInsert=false');
    });

    test('更新后 id 不变（保留原 id）', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        chapterListJs: 'old_list',
        chapterContentJs: 'old_content',
      );

      final result = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      expect(result.id, '1001', reason: '更新时 id 应保留原值');

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.id, '1001');
    });

    test('更新后 created_at 不变（保留原值）', () async {
      final originalCreatedAt = DateTime(2025, 1, 1).millisecondsSinceEpoch;
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        createdAt: originalCreatedAt,
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.createdAt, originalCreatedAt,
          reason: '更新时 created_at 应保留原值');
    });

    test('更新后 use_count 不重置（保留原值）', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        useCount: 42,
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.useCount, 42,
          reason: '更新时 use_count 应保留原值，不重置');
    });

    test('更新后 verified 重置为 0', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        verified: 1,
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.verified, 0,
          reason: '脚本内容变了，verified 应重置为 0');
    });

    test('更新后 last_used_at 刷新为当前时间', () async {
      final oldLastUsedAt = DateTime(2025, 1, 1).millisecondsSinceEpoch;
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        lastUsedAt: oldLastUsedAt,
      );

      // 等待一点时间确保 last_used_at 有明显差异
      await Future.delayed(const Duration(milliseconds: 50));

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.lastUsedAt, greaterThan(oldLastUsedAt),
          reason: '更新时 last_used_at 应刷新为当前时间');
    });

    test('更新后脚本内容已替换', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
        chapterListJs: 'old_list',
        chapterContentJs: 'old_content',
        urlPattern: '/old/',
        sampleUrl: 'https://old.example.com',
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
        urlPattern: '/new/',
        sampleUrl: 'https://new.example.com',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.chapterListJs, 'new_list');
      expect(saved.chapterContentJs, 'new_content');
      expect(saved.urlPattern, '/new/');
      expect(saved.sampleUrl, 'https://new.example.com');
    });

    test('更新后数据库中只有一条记录', () async {
      await insertRawScript(
        id: '1001',
        domain: 'www.example.com',
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      expect(await countByDomain('www.example.com'), 1,
          reason: '更新不应产生新记录');
    });
  });

  // ===== 清理重复记录 =====

  group('upsertByDomain - 清理历史重复记录', () {
    test('同 domain 多条记录时，保留第一条删除其余', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 插入 3 条同 domain 记录，按 last_used_at 降序
      await insertRawScript(
        id: 'old-1',
        domain: 'www.example.com',
        lastUsedAt: now - 3000,
      );
      await insertRawScript(
        id: 'old-2',
        domain: 'www.example.com',
        lastUsedAt: now - 2000,
      );
      await insertRawScript(
        id: 'old-3',
        domain: 'www.example.com',
        lastUsedAt: now - 1000,
      );

      // 确认数据准备正确：3 条记录
      expect(await countByDomain('www.example.com'), 3);

      final result = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      // UPDATE 了 last_used_at 最大的那条（old-3）
      expect(result.isInsert, isFalse);
      expect(result.id, 'old-3',
          reason: '应保留 last_used_at 最大的那条记录的 id');

      // 清理后只剩 1 条
      expect(await countByDomain('www.example.com'), 1,
          reason: '重复记录应被清理');
    });

    test('清理时保留原记录的 use_count', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertRawScript(
        id: 'keep',
        domain: 'www.example.com',
        useCount: 99,
        lastUsedAt: now,
      );
      await insertRawScript(
        id: 'duplicate',
        domain: 'www.example.com',
        useCount: 5,
        lastUsedAt: now - 1000,
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.useCount, 99,
          reason: '保留的记录应保持原 use_count');
    });

    test('清理不影响其他 domain 的记录', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertRawScript(
        id: 'dup-1',
        domain: 'www.example.com',
        lastUsedAt: now - 1000,
      );
      await insertRawScript(
        id: 'dup-2',
        domain: 'www.example.com',
        lastUsedAt: now,
      );
      await insertRawScript(
        id: 'other-1',
        domain: 'www.other-site.com',
        lastUsedAt: now,
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'new_list',
        chapterContentJs: 'new_content',
      );

      expect(await countByDomain('www.example.com'), 1,
          reason: '目标 domain 应清理为 1 条');
      expect(await countByDomain('www.other-site.com'), 1,
          reason: '其他 domain 不受影响');
    });
  });

  // ===== 边界情况 =====

  group('upsertByDomain - 边界情况', () {
    test('连续两次 upsert 同 domain，第二次为 UPDATE', () async {
      final r1 = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'v1_list',
        chapterContentJs: 'v1_content',
      );
      expect(r1.isInsert, isTrue);

      final r2 = await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'v2_list',
        chapterContentJs: 'v2_content',
      );
      expect(r2.isInsert, isFalse);
      expect(r2.id, r1.id, reason: '第二次应更新同一条记录，id 不变');

      expect(await countByDomain('www.example.com'), 1,
          reason: '两次 upsert 后仍只有 1 条记录');

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.chapterListJs, 'v2_list',
          reason: '内容应为第二次 upsert 的值');
    });

    test('upsert 后 getByDomain 返回最新数据', () async {
      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'v1',
        chapterContentJs: 'c1',
      );

      await repo.upsertByDomain(
        domain: 'www.example.com',
        chapterListJs: 'v2',
        chapterContentJs: 'c2',
      );

      final saved = await repo.getByDomain('www.example.com');
      expect(saved!.chapterListJs, 'v2');
      expect(saved.chapterContentJs, 'c2');
    });
  });

  // ===== updateScriptPart（分次增量更新） =====

  group('updateScriptPart', () {
    test('分次写 list/content 不互相覆盖；各自 ocr 写到对应列；domain 不存在自动 create', () async {
      // 先插一条种子记录（两列都有值，验证 update 不覆盖未触及列）
      await repo.upsertByDomain(
        domain: 'fanqienovel.com',
        chapterListJs: 'LIST_SEED',
        chapterContentJs: 'CONTENT_SEED',
        chapterListOcr: false,
        chapterContentOcr: false,
      );

      // 第一次：只写 chapter_list_js（番茄场景：目录页无 PUA，ocr=false）
      await repo.updateScriptPart(
        domain: 'fanqienovel.com',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_NEW',
        ocr: false,
      );
      final after1 = await repo.getByDomain('fanqienovel.com');
      expect(after1!.chapterListJs, 'LIST_NEW');
      expect(after1.chapterContentJs, 'CONTENT_SEED', reason: '未触及列应保持原值');
      expect(after1.chapterListOcr, isFalse);
      expect(after1.chapterContentOcr, isFalse);
      expect(after1.verified, 0, reason: '脚本内容变了，verified 应重置为 0');

      // 第二次：只写 chapter_content_js（番茄场景：正文页有 PUA，ocr=true）
      await repo.updateScriptPart(
        domain: 'fanqienovel.com',
        scriptType: 'chapter_content',
        scriptJs: 'CONTENT_NEW',
        ocr: true,
      );
      final after2 = await repo.getByDomain('fanqienovel.com');
      expect(after2!.chapterListJs, 'LIST_NEW', reason: '第一次写入的不应丢失');
      expect(after2.chapterContentJs, 'CONTENT_NEW');
      // 关键：list 的 ocr 不被 content 的写入覆盖
      expect(after2.chapterListOcr, isFalse,
          reason: 'list 的 ocr 不应被 content 写入覆盖');
      expect(after2.chapterContentOcr, isTrue);
    });

    test('domain 不存在时自动 INSERT 新记录，本列写脚本另一列留空', () async {
      final result = await repo.updateScriptPart(
        domain: 'not.exist',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_FIRST',
        ocr: false,
      );
      expect(result.success, isTrue);
      expect(result.reason, isNull);
      expect(result.id, isNotNull);

      final row = await repo.getByDomain('not.exist');
      expect(row, isNotNull);
      expect(row!.chapterListJs, 'LIST_FIRST');
      expect(row.chapterContentJs, '',
          reason: '未保存的另一半应留空，由后续 save_script 补齐');
      expect(row.verified, 0);
      expect(row.chapterListOcr, isFalse,
          reason: 'chapter_list 类型 + ocr=false → 该列写 false');
      expect(row.chapterContentOcr, isFalse,
          reason: '未保存的另一半 ocr 应保持默认 false');
    });

    test('domain 不存在时 chapter_content 第一次也能直接落库', () async {
      final result = await repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'CONTENT_FIRST',
        ocr: true,
      );
      expect(result.success, isTrue);
      final row = await repo.getByDomain('a.com');
      expect(row!.chapterListJs, '');
      expect(row.chapterContentJs, 'CONTENT_FIRST');
      expect(row.chapterContentOcr, isTrue,
          reason: 'chapter_content 类型 + ocr=true → 该列写 true');
      expect(row.chapterListOcr, isFalse,
          reason: '未保存的另一半 ocr 应保持默认 false');
      expect(row.verified, 0);
    });

    test('首次 INSERT 后第二次 update：覆盖本列、保持另一列、verified 仍为 0', () async {
      await repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_V1',
        ocr: false,
      );
      await repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'CONTENT_V1',
        ocr: false,
      );
      final row = await repo.getByDomain('a.com');
      expect(row!.chapterListJs, 'LIST_V1');
      expect(row.chapterContentJs, 'CONTENT_V1');
      expect(row.verified, 0);
    });
  });

  // ===== upsertByDomain 两列 ocr 参数（v39 拆列后） =====

  group('upsertByDomain 两列 ocr', () {
    test('番茄场景：chapterListOcr=false, chapterContentOcr=true 各自落库', () async {
      await repo.upsertByDomain(
        domain: 'a.com',
        chapterListJs: 'L',
        chapterContentJs: 'C',
        chapterListOcr: false,
        chapterContentOcr: true,
      );
      final s = (await repo.getByDomain('a.com'))!;
      expect(s.chapterListOcr, isFalse);
      expect(s.chapterContentOcr, isTrue);
    });

    test('两列 ocr 默认 false（向后兼容）', () async {
      await repo.upsertByDomain(
        domain: 'b.com',
        chapterListJs: 'L',
        chapterContentJs: 'C',
      );
      final s = (await repo.getByDomain('b.com'))!;
      expect(s.chapterListOcr, isFalse);
      expect(s.chapterContentOcr, isFalse);
    });
  });
}
