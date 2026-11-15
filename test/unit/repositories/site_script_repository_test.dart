import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../helpers/test_database_setup.dart';

/// SiteScriptRepository 单元测试
///
/// 使用真实内存数据库，验证生产写路径 [SiteScriptRepository.updateScriptPart]
/// 的核心分支（分次增量保存 / 自动建行 / ocr 列独立 / 显示名语义）。
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

  // ===== updateScriptPart（分次增量更新） =====

  group('updateScriptPart', () {
    test('分次写 list/content 不互相覆盖；各自 ocr 写到对应列；domain 不存在自动 create', () async {
      // 先造种子记录（两列都有值，验证 update 不覆盖未触及列）——走生产写路径
      await repo.updateScriptPart(
        domain: 'fanqienovel.com',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_SEED',
        ocr: false,
      );
      await repo.updateScriptPart(
        domain: 'fanqienovel.com',
        scriptType: 'chapter_content',
        scriptJs: 'CONTENT_SEED',
        ocr: false,
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

    test('bookshelf 类型：domain 不存在自动 INSERT，ocr 列不受影响', () async {
      final result = await repo.updateScriptPart(
        domain: 'bs.com',
        scriptType: 'bookshelf',
        scriptJs: 'BOOKSHELF_FIRST',
        ocr: false,
      );
      expect(result.success, isTrue);
      final row = await repo.getByDomain('bs.com');
      expect(row, isNotNull);
      expect(row!.bookshelfJs, 'BOOKSHELF_FIRST');
      expect(row.chapterListJs, '', reason: '其它列应留空串占位');
      expect(row.chapterContentJs, '');
      expect(row.chapterListOcr, isFalse);
      expect(row.chapterContentOcr, isFalse);
      expect(row.hasBookshelfJs, isTrue);
    });

    test('bookshelf 类型更新已存在行：只写 bookshelf_js，不动 ocr 列与其它脚本', () async {
      // 种子：list ocr=true，content ocr=false
      await repo.updateScriptPart(
        domain: 'mixed.com',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_SEED',
        ocr: true,
      );
      await repo.updateScriptPart(
        domain: 'mixed.com',
        scriptType: 'chapter_content',
        scriptJs: 'CONTENT_SEED',
        ocr: false,
      );

      // 保存 bookshelf（ocr 参数无论传什么都应被忽略）
      final result = await repo.updateScriptPart(
        domain: 'mixed.com',
        scriptType: 'bookshelf',
        scriptJs: 'BOOKSHELF_NEW',
        ocr: true, // 故意传 true，验证被忽略
      );
      expect(result.success, isTrue);

      final row = await repo.getByDomain('mixed.com');
      expect(row!.bookshelfJs, 'BOOKSHELF_NEW');
      expect(row.chapterListJs, 'LIST_SEED', reason: 'bookshelf 写入不应覆盖其它脚本');
      expect(row.chapterContentJs, 'CONTENT_SEED');
      expect(row.chapterListOcr, isTrue, reason: 'bookshelf 不应触碰 list ocr 列');
      expect(row.chapterContentOcr, isFalse);
      expect(row.verified, 0);
    });

    test('传 testUrl → 写入 sample_url（刷新同步用它定位书架页）', () async {
      await repo.updateScriptPart(
        domain: 'u.com',
        scriptType: 'bookshelf',
        scriptJs: 'BS_V1',
        ocr: false,
        testUrl: 'https://u.com/my/favorites',
      );
      final row = await repo.getByDomain('u.com');
      expect(row!.sampleUrl, 'https://u.com/my/favorites');

      // 二次保存更新 URL → sample_url 跟随更新
      await repo.updateScriptPart(
        domain: 'u.com',
        scriptType: 'bookshelf',
        scriptJs: 'BS_V2',
        ocr: false,
        testUrl: 'https://u.com/fav2',
      );
      final row2 = await repo.getByDomain('u.com');
      expect(row2!.sampleUrl, 'https://u.com/fav2');
      expect(row2.bookshelfJs, 'BS_V2');
    });

    test('不传 testUrl → sample_url 保留历史值不动', () async {
      await repo.updateScriptPart(
        domain: 'keep.com',
        scriptType: 'bookshelf',
        scriptJs: 'BS_V1',
        ocr: false,
        testUrl: 'https://keep.com/fav',
      );
      await repo.updateScriptPart(
        domain: 'keep.com',
        scriptType: 'chapter_list',
        scriptJs: 'LIST_V1',
        ocr: false, // 不传 testUrl
      );
      final row = await repo.getByDomain('keep.com');
      expect(row!.sampleUrl, 'https://keep.com/fav',
          reason: '未传 testUrl 的保存不应清空已有 sample_url');
    });
  });

  // ===== 站点显示名（display_name，v45 起） =====

  group('updateScriptPart - displayName', () {
    test('首次保存带 displayName 时写入 display_name 列', () async {
      await repo.updateScriptPart(
        domain: 'www.qidian.com',
        scriptType: 'chapter_list',
        scriptJs: 'L',
        ocr: false,
        displayName: ' 起点中文网 ',
      );

      final s = (await repo.getByDomain('www.qidian.com'))!;
      expect(s.displayName, '起点中文网', reason: '应 trim 前后空白');
    });

    test('首次保存不带 displayName 时落空串', () async {
      await repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'C',
        ocr: false,
      );

      final s = (await repo.getByDomain('a.com'))!;
      expect(s.displayName, '');
    });

    test('分次保存不传 displayName 不清空已有值', () async {
      await repo.updateScriptPart(
        domain: 'b.com',
        scriptType: 'chapter_list',
        scriptJs: 'L',
        ocr: false,
        displayName: '番茄小说',
      );
      await repo.updateScriptPart(
        domain: 'b.com',
        scriptType: 'chapter_content',
        scriptJs: 'C',
        ocr: false,
      );

      final s = (await repo.getByDomain('b.com'))!;
      expect(s.chapterContentJs, 'C');
      expect(s.displayName, '番茄小说', reason: '第二次保存未传名应保留原值');
    });

    test('显式传新 displayName 覆盖旧值', () async {
      await repo.updateScriptPart(
        domain: 'c.com',
        scriptType: 'chapter_list',
        scriptJs: 'L',
        ocr: false,
        displayName: '旧名',
      );
      await repo.updateScriptPart(
        domain: 'c.com',
        scriptType: 'chapter_content',
        scriptJs: 'C',
        ocr: false,
        displayName: '新名',
      );

      final s = (await repo.getByDomain('c.com'))!;
      expect(s.displayName, '新名');
    });
  });

  group('getDisplayNamesByDomain', () {
    test('仅返回 display_name 非空的行，键小写化', () async {
      await repo.updateScriptPart(
        domain: 'WWW.Qidian.com',
        scriptType: 'chapter_list',
        scriptJs: 'L',
        ocr: false,
        displayName: '起点中文网',
      );
      await repo.updateScriptPart(
        domain: 'plain.com',
        scriptType: 'chapter_list',
        scriptJs: 'L',
        ocr: false,
      );

      final names = await repo.getDisplayNamesByDomain();
      expect(names, {'www.qidian.com': '起点中文网'});
    });

    test('无任何登记名时返回空 Map', () async {
      expect(await repo.getDisplayNamesByDomain(), isEmpty);
    });
  });
}
