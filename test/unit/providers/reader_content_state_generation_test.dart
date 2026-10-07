import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/reader_state_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/novel.dart';

/// ChapterContentStateNotifier 加载世代守卫单测。
///
/// 回归背景：loadChapter 的抓取是秒级异步，await 期间滚动切章会直接写入
/// 新章内容；旧抓取落地后无条件 setContent 把 A 的内容写进 B 的状态
/// （B 标题下显示 A 正文），下游 syncCurrentBlockFrom 的守卫比较的是被
/// 污染后的 currentChapter，挡不住。世代号让过期写入在源头被丢弃。
void main() {
  final novel = Novel(title: '测试小说', author: '作者', url: 'custom://n1');
  final chapterA = Chapter(title: '第一章', url: 'a1');
  final chapterB = Chapter(title: '第二章', url: 'b1');

  late ProviderContainer container;
  late ChapterContentStateNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(chapterContentStateNotifierProvider.notifier);
  });

  ChapterContentState readState() => container.read(chapterContentStateNotifierProvider);

  test('setCurrentContext 开新世代并返回世代号', () {
    final gen1 = notifier.setCurrentContext(chapterA, novel);
    final gen2 = notifier.setCurrentContext(chapterB, novel);
    expect(gen2, greaterThan(gen1));
  });

  test('切章后旧世代抓取落地 → finishLoad 丢弃，不覆盖新章内容', () {
    final staleGen = notifier.setCurrentContext(chapterA, novel);
    notifier.setLoading(true);

    // 期间切到 B
    final currentGen = notifier.setCurrentContext(chapterB, novel);
    notifier.setContent('B 的正文');

    // 旧章（A）抓取姗姗来迟 → 丢弃
    expect(notifier.finishLoad(staleGen, 'A 的正文'), isFalse,
        reason: '过期世代必须被丢弃——否则 B 标题下显示 A 的正文');
    expect(readState().content, 'B 的正文',
        reason: '新章内容不得被过期写入覆盖');
    expect(readState().currentChapter!.url, 'b1');

    // 当前世代的回写正常生效
    expect(notifier.finishLoad(currentGen, 'B 的最终正文'), isTrue);
    expect(readState().content, 'B 的最终正文');
  });

  test('切章后旧世代失败回写 → failLoad 丢弃，不覆盖新章错误态', () {
    final staleGen = notifier.setCurrentContext(chapterA, novel);

    notifier.setCurrentContext(chapterB, novel);
    notifier.setError('B 加载失败');

    expect(notifier.failLoad(staleGen, 'A 加载失败'), isFalse,
        reason: '过期失败不得清掉新章的错误提示');
    expect(readState().errorMessage, 'B 加载失败');

    // 任意过期世代号同样被拒
    expect(notifier.failLoad(9999, '过期'), isFalse);
  });

  test('当前世代回写正常生效（守卫不影响正常路径）', () {
    final gen = notifier.setCurrentContext(chapterA, novel);
    notifier.setLoading(true);

    expect(notifier.finishLoad(gen, 'A 的正文'), isTrue);
    expect(readState().content, 'A 的正文');
    expect(readState().isLoading, isFalse);
  });
}
