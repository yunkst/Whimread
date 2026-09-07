import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_version_repository.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/chapter_version.dart';
import 'package:novel_app/repositories/chapter_repository.dart'
    show IChapterWriter;
import 'package:novel_app/widgets/reader/version_history_sheet.dart';

/// 记录写调用的假 IChapterWriter（仅需验证 updateChapterContent 是否被收口调用）
class _RecordingWriter implements IChapterWriter {
  final List<({String chapterUrl, String content, String source})>
      updateContentCalls = [];

  @override
  Future<int> updateChapterContent(String chapterUrl, String content,
      {String source = 'edit'}) async {
    updateContentCalls.add(
      (chapterUrl: chapterUrl, content: content, source: source),
    );
    return 1;
  }

  @override
  Future<int> cacheChapter(
      String novelUrl, Chapter chapter, String content) async {
    return 1;
  }

  @override
  Future<int> updateChapterContentById(int id, String content) async => 1;

  @override
  Future<int> deleteChapterCache(String chapterUrl) async => 1;

  @override
  Future<int> deleteCachedChapters(String novelUrl) async => 1;

  @override
  Future<void> cacheNovelChapters(
      String novelUrl, List<Chapter> chapters) async {}

  @override
  Future<int> createCustomChapter(String novelUrl, String title,
      String content, [int? index]) async =>
      1;

  @override
  Future<void> updateCustomChapter(
      String chapterUrl, String title, String content) async {}

  @override
  Future<void> deleteCustomChapter(String chapterUrl) async {}

  @override
  Future<void> shiftChapterIndicesFrom(String novelUrl, int fromIndex) async {}

  @override
  Future<void> updateChaptersOrder(
      String novelUrl, List<Chapter> chapters) async {}

  @override
  Future<void> markChapterAsRead(String novelUrl, String chapterUrl) async {}

  @override
  Future<int> createCustomChapterWithShift(
      String novelUrl, String title, String content,
      [int? insertIndex]) async =>
      1;

  @override
  Future<void> deleteChapterAndReindex(
      String novelUrl, String chapterUrl) async {}
}

/// 记录删除调用的假版本仓库
class _RecordingVersionRepo implements IChapterVersionRepository {
  final List<ChapterVersion> versions;
  final List<int> deletedIds = [];

  _RecordingVersionRepo(this.versions);

  @override
  Future<int> saveVersion(ChapterVersion version) async => 1;

  @override
  Future<List<ChapterVersion>> getVersions(String chapterUrl) async => versions;

  @override
  Future<int> getVersionCount(String chapterUrl) async => versions.length;

  @override
  Future<ChapterVersion?> getVersionById(int id) async {
    for (final v in versions) {
      if (v.id == id) return v;
    }
    return null;
  }

  @override
  Future<int> deleteVersion(int id) async {
    deletedIds.add(id);
    return 1;
  }

  @override
  Future<int> deleteVersionsByChapter(String chapterUrl) async => 1;

  @override
  Future<int> deleteVersionsByNovel(String novelUrl) async => 1;

  @override
  Future<int> evictOldestVersions(String chapterUrl,
      {int maxCount = 5}) async =>
      0;
}

/// 版本历史面板 · 还原/删除生命周期测试
///
/// 回归背景：面板先 pop 自己再弹二次确认框。pop 退出动画结束后面板 State 被
/// dispose，用户在确认框点「还原」时 `!mounted` 早退，写库根本不执行——
/// 表现为「选择历史版本，切换不回去」。本测试模拟真实时序：确认框打开期间
/// pumpAndSettle 让面板退出动画走完（State 已 dispose），再确认。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // mock Fluttertoast 插件 channel，避免成功 toast 抛 MissingPluginException
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('Fluttertoast'),
      (MethodCall call) async => true,
    );
  });

  ChapterVersion buildVersion({
    int id = 1,
    String content = '历史内容B',
  }) {
    return ChapterVersion(
      chapterUrl: 'url1',
      content: content,
      source: 'edit',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      contentLength: content.length,
      id: id,
    );
  }

  Future<({
    _RecordingWriter writer,
    _RecordingVersionRepo versionRepo,
  })> openSheet(
    WidgetTester tester, {
    required List<ChapterVersion> versions,
    required VoidCallback onRestored,
  }) async {
    final writer = _RecordingWriter();
    final versionRepo = _RecordingVersionRepo(versions);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chapterWriterProvider.overrideWithValue(writer),
          chapterVersionRepositoryProvider.overrideWithValue(versionRepo),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => VersionHistorySheet.show(
                    context,
                    chapterUrl: 'url1',
                    chapterTitle: '第一章',
                    novelUrl: 'novel1',
                    onRestored: onRestored,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (writer: writer, versionRepo: versionRepo);
  }

  testWidgets('确认还原：面板关闭后确认仍应执行还原并回调 onRestored', (tester) async {
    var restoredCount = 0;
    final deps = await openSheet(
      tester,
      versions: [buildVersion()],
      onRestored: () => restoredCount++,
    );

    expect(find.text('1个版本'), findsOneWidget);

    // 点版本条目的「还原」→ 弹二次确认框
    await tester.tap(find.byTooltip('还原'));
    await tester.pumpAndSettle(); // 关键：让面板退出动画走完，模拟真实设备上
    // 用户停留在确认框数秒的时序（此时面板 State 已 dispose）

    // 确认框里点「还原」
    await tester.tap(find.widgetWithText(FilledButton, '还原'));
    await tester.pumpAndSettle();

    expect(deps.writer.updateContentCalls, hasLength(1));
    expect(deps.writer.updateContentCalls.first.chapterUrl, 'url1');
    expect(deps.writer.updateContentCalls.first.content, '历史内容B');
    expect(deps.writer.updateContentCalls.first.source, 'restore');
    expect(restoredCount, 1);
  });

  testWidgets('取消还原：不应执行任何写操作', (tester) async {
    var restoredCount = 0;
    final deps = await openSheet(
      tester,
      versions: [buildVersion()],
      onRestored: () => restoredCount++,
    );

    await tester.tap(find.byTooltip('还原'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(deps.writer.updateContentCalls, isEmpty);
    expect(restoredCount, 0);
  });

  testWidgets('确认删除：面板关闭后确认仍应删除版本', (tester) async {
    final deps = await openSheet(
      tester,
      versions: [buildVersion(id: 7)],
      onRestored: () {},
    );

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deps.versionRepo.deletedIds, [7]);
  });
}
