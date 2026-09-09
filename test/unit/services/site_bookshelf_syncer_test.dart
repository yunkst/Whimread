/// SiteBookshelfSyncer 纯合并逻辑单元测试
///
/// 覆盖：
/// - 全部新增（本地为空）
/// - 部分已存在（跳过、保留本地）
/// - 全部已存在
/// - 单本 addNovel 抛异常不中断整批
/// - progress 回调计数
/// - summary 文案
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/site_bookshelf_entry.dart';
import 'package:novel_app/services/site_bookshelf_syncer.dart';

void main() {
  const entries = [
    SiteBookshelfEntry(title: '新书A', url: 'https://a.com/1'),
    SiteBookshelfEntry(title: '已有B', url: 'https://a.com/2'),
    SiteBookshelfEntry(title: '新书C', url: 'https://a.com/3'),
  ];

  group('SiteBookshelfSyncer.sync', () {
    test('本地为空 → 全部新增', () async {
      final addedNovels = <String>[];
      final result = await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: (_) async => false,
        addNovel: (novel) async => addedNovels.add(novel.url),
      );

      expect(result.added, 3);
      expect(result.alreadyExists, 0);
      expect(result.totalFromSite, 3);
      expect(addedNovels, hasLength(3));
      expect(addedNovels.first, 'https://a.com/1');
    });

    test('部分已存在 → 已存在的跳过（不重复 addNovel）', () async {
      final addedNovels = <String>[];
      final result = await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: (url) async => url == 'https://a.com/2',
        addNovel: (novel) async => addedNovels.add(novel.url),
      );

      expect(result.added, 2);
      expect(result.alreadyExists, 1);
      expect(addedNovels, ['https://a.com/1', 'https://a.com/3']);
    });

    test('全部已存在 → 零新增，summary 提示已存在', () async {
      final addedNovels = <String>[];
      final result = await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: (_) async => true,
        addNovel: (novel) async => addedNovels.add(novel.url),
      );

      expect(result.added, 0);
      expect(result.alreadyExists, 3);
      expect(addedNovels, isEmpty);
      expect(result.summary, '已存在 3 本');
    });

    test('单本 addNovel 抛异常 → 不中断整批', () async {
      var calls = 0;
      final result = await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: (_) async => false,
        addNovel: (novel) async {
          calls++;
          if (novel.url == 'https://a.com/2') throw StateError('db locked');
        },
      );

      // 三本都尝试过（异常被吞），计为 added=3（异常被吞不加区分，简化语义）
      expect(calls, 3);
      expect(result.totalFromSite, 3);
    });

    test('progress 回调逐条推进', () async {
      final processedList = <int>[];
      await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: (_) async => false,
        addNovel: (_) async {},
        progress: (p) => processedList.add(p.processed),
      );
      expect(processedList, [1, 2, 3]);
    });

    test('summary 文案组合', () {
      const r1 = SiteBookshelfSyncResult(
          added: 2, alreadyExists: 1, totalFromSite: 3);
      expect(r1.summary, '新增 2 本，已存在 1 本');

      const r2 = SiteBookshelfSyncResult(
          added: 0, alreadyExists: 0, totalFromSite: 0);
      expect(r2.summary, '未发现可同步内容');
    });
  });
}