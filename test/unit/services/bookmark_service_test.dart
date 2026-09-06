// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/services/bookmark_service.dart';

/// BookmarkService 单元测试
///
/// 覆盖：
/// - 旧数据（无 groupId 字段）的向后兼容加载
/// - 分组增删改 + 同名去重
/// - deleteGroup 后组内收藏归入「未分组」
/// - 收藏的重命名 / 移动 / 删除持久化
void main() {
  late BookmarkService service;

  setUp(() async {
    // setMockInitialValues 只影响未来 getInstance 拿到的实例，
    // 必须先 clear() 才能彻底重置已持有的实例状态。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    service = BookmarkService(prefs);
  });

  group('向后兼容', () {
    test('旧数据无 groupId 字段 → 加载后归入未分组', () async {
      // 模拟旧版本写入的收藏数据（不含 groupId 键）
      final legacy = {
        'id': '1',
        'title': '笔趣阁',
        'url': 'https://biquge.com',
        'createdAt': '2026-01-01T00:00:00',
      };
      await _writeRawBookmarks([jsonEncode(legacy)]);

      final bookmarks = service.loadBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks.first.groupId, isNull);
      expect(bookmarks.first.title, '笔趣阁');
    });

    test('无 groups key → loadGroups 返回空列表', () {
      final groups = service.loadGroups();
      expect(groups, isEmpty);
    });
  });

  group('分组管理', () {
    test('addGroup 正常创建', () async {
      final g = await service.addGroup('小说站点');
      final groups = service.loadGroups();
      expect(groups.length, 1);
      expect(groups.first.id, g.id);
      expect(groups.first.name, '小说站点');
    });

    test('addGroup 同名自动追加后缀', () async {
      await service.addGroup('工具');
      await service.addGroup('工具');
      final groups = service.loadGroups();
      expect(groups.length, 2);
      expect(groups.map((g) => g.name).toList(), ['工具', '工具 (2)']);
    });

    test('renameGroup 正常重命名', () async {
      final g = await service.addGroup('旧名');
      await service.renameGroup(g.id, '新名');
      expect(service.loadGroups().first.name, '新名');
    });

    test('renameGroup 同名时自动追加后缀', () async {
      final a = await service.addGroup('A');
      await service.addGroup('B');
      await service.renameGroup(a.id, 'B');
      final groups = service.loadGroups();
      final a2 = groups.firstWhere((g) => g.id == a.id);
      // 重命名后的名字不应与已有 'B' 冲突
      expect(a2.name, 'B (2)');
      // 总数不变
      expect(groups.length, 2);
    });

    test('deleteGroup 把组内收藏归入未分组', () async {
      final g = await service.addGroup('小说站点');
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: '笔趣阁',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
        groupId: g.id,
      ));
      await service.addBookmark(Bookmark(
        id: 'b2',
        title: '顶点',
        url: 'https://b2.com',
        createdAt: DateTime(2026, 1, 2),
        groupId: g.id,
      ));

      expect(service.loadGroups().length, 1);
      await service.deleteGroup(g.id);

      expect(service.loadGroups(), isEmpty);
      final bookmarks = service.loadBookmarks();
      expect(bookmarks.length, 2);
      expect(bookmarks.every((b) => b.groupId == null), isTrue);
    });

    test('deleteGroup 不影响其他分组的收藏', () async {
      final g1 = await service.addGroup('G1');
      final g2 = await service.addGroup('G2');
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: 't1',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
        groupId: g1.id,
      ));
      await service.addBookmark(Bookmark(
        id: 'b2',
        title: 't2',
        url: 'https://b2.com',
        createdAt: DateTime(2026, 1, 2),
        groupId: g2.id,
      ));

      await service.deleteGroup(g1.id);

      final bookmarks = service.loadBookmarks();
      // b1 归入未分组，b2 仍在 g2
      final b1 = bookmarks.firstWhere((b) => b.id == 'b1');
      final b2 = bookmarks.firstWhere((b) => b.id == 'b2');
      expect(b1.groupId, isNull);
      expect(b2.groupId, g2.id);
    });
  });

  group('收藏操作', () {
    test('addBookmark 同 URL 替换旧项', () async {
      await service.addBookmark(Bookmark(
        id: 'old',
        title: '旧标题',
        url: 'https://same.com',
        createdAt: DateTime(2026, 1, 1),
      ));
      await service.addBookmark(Bookmark(
        id: 'new',
        title: '新标题',
        url: 'https://same.com',
        createdAt: DateTime(2026, 1, 2),
      ));

      final bookmarks = service.loadBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks.first.id, 'new');
      expect(bookmarks.first.title, '新标题');
    });

    test('addBookmark 保留 groupId 归属', () async {
      final g = await service.addGroup('小说站点');
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: '笔趣阁',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
        groupId: g.id,
      ));

      final bookmarks = service.loadBookmarks();
      expect(bookmarks.first.groupId, g.id);
    });

    test('renameBookmark 持久化新标题', () async {
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: '旧名',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
      ));
      await service.renameBookmark('b1', '新名');
      expect(service.loadBookmarks().first.title, '新名');
    });

    test('renameBookmark 空标题被拒绝', () async {
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: '原标题',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
      ));
      await service.renameBookmark('b1', '   ');
      expect(service.loadBookmarks().first.title, '原标题');
    });

    test('moveBookmark 跨分组持久化', () async {
      final g1 = await service.addGroup('G1');
      final g2 = await service.addGroup('G2');
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: 't',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
        groupId: g1.id,
      ));

      await service.moveBookmark('b1', g2.id);
      expect(service.loadBookmarks().first.groupId, g2.id);

      // 移到未分组
      await service.moveBookmark('b1', null);
      expect(service.loadBookmarks().first.groupId, isNull);
    });

    test('removeBookmark 删除指定项', () async {
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: 't',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
      ));
      await service.removeBookmark('b1');
      expect(service.loadBookmarks(), isEmpty);
    });

    test('isBookmarked 正确识别已收藏 URL', () async {
      await service.addBookmark(Bookmark(
        id: 'b1',
        title: 't',
        url: 'https://b1.com',
        createdAt: DateTime(2026, 1, 1),
      ));
      expect(service.isBookmarked('https://b1.com'), isTrue);
      expect(service.isBookmarked('https://other.com'), isFalse);
    });
  });

  group('Bookmark 模型序列化', () {
    test('toJson / fromJson 往返保持字段', () {
      final original = Bookmark(
        id: 'x',
        title: '标题',
        url: 'https://x.com',
        groupId: 'g1',
        createdAt: DateTime(2026, 7, 6, 12, 0),
      );
      final decoded = Bookmark.fromJson(original.toJson());
      expect(decoded.id, original.id);
      expect(decoded.title, original.title);
      expect(decoded.url, original.url);
      expect(decoded.groupId, original.groupId);
      expect(decoded.createdAt, original.createdAt);
    });

    test('groupId 为 null 时 toJson 不写入该键', () {
      final b = Bookmark(
        id: 'x',
        title: 't',
        url: 'https://x.com',
        createdAt: DateTime(2026, 7, 6),
      );
      final json = b.toJson();
      expect(json.containsKey('groupId'), isFalse);
    });
  });
}

/// 直接写入 SharedPreferences 模拟旧版数据
Future<void> _writeRawBookmarks(List<String> rawList) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('browser_bookmarks', rawList);
}
