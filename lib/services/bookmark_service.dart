import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';

/// 浏览器收藏夹数据模型
class Bookmark {
  final String id;
  final String title;
  final String url;
  final String? groupId; // null = 未分组（兼容旧数据）
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.title,
    required this.url,
    required this.createdAt,
    this.groupId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        if (groupId != null) 'groupId': groupId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        // 旧数据无此字段，容错读取避免整条记录被丢弃
        groupId: json['groupId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 收藏分组数据模型
///
/// 分组按 `createdAt` 升序展示；删除分组后其下收藏自动归入「未分组」。
class BookmarkGroup {
  final String id;
  final String name;
  final DateTime createdAt;

  BookmarkGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BookmarkGroup.fromJson(Map<String, dynamic> json) => BookmarkGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookmarkGroup &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 浏览器收藏夹持久化服务
class BookmarkService {
  static const _bookmarkKey = 'browser_bookmarks';
  static const _groupKey = 'browser_bookmark_groups';

  final SharedPreferences _prefs;

  BookmarkService(this._prefs);

  // 进程内自增计数器，与时间戳组合生成唯一 id，
  // 避免同一毫秒内连续 addGroup 产生相同 id（导致分组互相覆盖/去重失效）。
  static int _idCounter = 0;

  /// 生成全局唯一 id（时间戳 + 自增计数器）
  static String _generateId() {
    _idCounter += 1;
    return '${DateTime.now().millisecondsSinceEpoch}-$_idCounter';
  }

  // ============================================================
  // 收藏（Bookmark）相关
  // ============================================================

  /// 加载所有收藏（按 createdAt 倒序）
  List<Bookmark> loadBookmarks() {
    try {
      final raw = _prefs.getStringList(_bookmarkKey);
      if (raw == null) return [];
      return raw
          .map((s) {
            try {
              return Bookmark.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<Bookmark>()
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载收藏夹失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'load', 'error'],
      );
      return [];
    }
  }

  /// 保存所有收藏
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    try {
      final raw =
          bookmarks.map((b) => jsonEncode(b.toJson())).toList();
      await _prefs.setStringList(_bookmarkKey, raw);
      LoggerService.instance.d(
        '保存 ${bookmarks.length} 条收藏',
        category: LogCategory.database,
        tags: ['bookmark', 'save'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存收藏夹失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'save', 'error'],
      );
    }
  }

  /// 添加收藏（同 URL 视为同一项，被替换）
  Future<void> addBookmark(Bookmark bookmark) async {
    final bookmarks = loadBookmarks();
    final incoming = bookmark.copyWith(createdAt: DateTime.now());
    bookmarks.removeWhere((b) => b.url == incoming.url);
    bookmarks.add(incoming);
    await saveBookmarks(bookmarks);
  }

  /// 删除收藏
  Future<void> removeBookmark(String id) async {
    final bookmarks = loadBookmarks();
    bookmarks.removeWhere((b) => b.id == id);
    await saveBookmarks(bookmarks);
  }

  /// 重命名收藏
  Future<void> renameBookmark(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final bookmarks = loadBookmarks();
    final index = bookmarks.indexWhere((b) => b.id == id);
    if (index < 0) return;
    bookmarks[index] = bookmarks[index].copyWith(title: trimmed);
    await saveBookmarks(bookmarks);
  }

  /// 移动收藏到指定分组（groupId 为 null 表示「未分组」）
  Future<void> moveBookmark(String id, String? groupId) async {
    final bookmarks = loadBookmarks();
    final index = bookmarks.indexWhere((b) => b.id == id);
    if (index < 0) return;
    if (bookmarks[index].groupId == groupId) return;
    // 直接构造，避免 `null` 与「未传」在 copyWith 中混淆
    bookmarks[index] = Bookmark(
      id: bookmarks[index].id,
      title: bookmarks[index].title,
      url: bookmarks[index].url,
      groupId: groupId,
      createdAt: bookmarks[index].createdAt,
    );
    await saveBookmarks(bookmarks);
  }

  /// 检查 URL 是否已收藏
  bool isBookmarked(String url) {
    return loadBookmarks().any((b) => b.url == url);
  }

  // ============================================================
  // 分组（BookmarkGroup）相关
  // ============================================================

  /// 加载所有分组（按 createdAt 升序）
  List<BookmarkGroup> loadGroups() {
    try {
      final raw = _prefs.getStringList(_groupKey);
      if (raw == null) return [];
      return raw
          .map((s) {
            try {
              return BookmarkGroup.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<BookmarkGroup>()
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'load', 'error'],
      );
      return [];
    }
  }

  /// 保存所有分组
  Future<void> saveGroups(List<BookmarkGroup> groups) async {
    try {
      final raw = groups.map((g) => jsonEncode(g.toJson())).toList();
      await _prefs.setStringList(_groupKey, raw);
      LoggerService.instance.d(
        '保存 ${groups.length} 个收藏分组',
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'save'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'save', 'error'],
      );
    }
  }

  /// 添加分组（同名自动追加后缀，避免重名冲突）
  Future<BookmarkGroup> addGroup(String name) async {
    final groups = loadGroups();
    final trimmed = name.trim();
    final uniqueName = _uniqueName(trimmed, groups.map((g) => g.name).toSet());
    final group = BookmarkGroup(
      id: _generateId(),
      name: uniqueName,
      createdAt: DateTime.now(),
    );
    groups.add(group);
    await saveGroups(groups);
    return group;
  }

  /// 重命名分组（同名会被自动去重）
  Future<void> renameGroup(String id, String name) async {
    final groups = loadGroups();
    final index = groups.indexWhere((g) => g.id == id);
    if (index < 0) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final others =
        groups.where((g) => g.id != id).map((g) => g.name).toSet();
    groups[index] =
        groups[index].copyWith(name: _uniqueName(trimmed, others));
    await saveGroups(groups);
  }

  /// 删除分组，并把其下收藏的 groupId 全部清空（归入「未分组」）
  Future<void> deleteGroup(String id) async {
    final bookmarks = loadBookmarks();
    var changed = false;
    for (var i = 0; i < bookmarks.length; i++) {
      if (bookmarks[i].groupId == id) {
        final b = bookmarks[i];
        // 显式清空 groupId（copyWith 用 ?? 合并，无法区分"清空"与"不变"）
        bookmarks[i] = Bookmark(
          id: b.id,
          title: b.title,
          url: b.url,
          groupId: null,
          createdAt: b.createdAt,
        );
        changed = true;
      }
    }
    final gs = loadGroups();
    final gIndex = gs.indexWhere((g) => g.id == id);
    if (gIndex >= 0) {
      gs.removeAt(gIndex);
      await saveGroups(gs);
    }
    if (changed) await saveBookmarks(bookmarks);
  }

  /// 唯一化分组名（同名追加「(2)/(3)...」）
  String _uniqueName(String name, Set<String> existing) {
    if (!existing.contains(name)) return name;
    var candidate = name;
    var counter = 2;
    while (existing.contains(candidate)) {
      candidate = '$name ($counter)';
      counter++;
    }
    return candidate;
  }
}

/// `copyWith` 便捷扩展，避免重复样板。
///
/// 语义：所有字段用 `??` 合并——传 `null` 视为「保持原值不变」。
/// 因此**不适用于「显式清空 groupId」的场景**（移动到未分组）；
/// 那个场景请直接 new 一个 `Bookmark`。
extension BookmarkCopyWith on Bookmark {
  Bookmark copyWith({
    String? id,
    String? title,
    String? url,
    String? groupId,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

extension BookmarkGroupCopyWith on BookmarkGroup {
  BookmarkGroup copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return BookmarkGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
