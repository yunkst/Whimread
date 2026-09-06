/// MediaView 媒体播放决策单元测试
///
/// 覆盖两个纯函数（离屏 pause 行为的大脑，零依赖、可单测）：
/// - [mediaPlayHysteresis]：可见性双阈值迟滞（0.1/0.5），防 fling 抖动
/// - [mediaVideoPlayCommand]：shouldPlay ↔ isPlaying → play/pause/none，防重复调用
///
/// 运行：
///   cd novel_app
///   flutter test test/unit/widgets/media_play_decision_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/media/media_view.dart';

void main() {
  group('mediaPlayHysteresis - 不可见 → 可见（升过 play 阈值 0.5）', () {
    test('fraction=0 不应转可见', () {
      expect(
        mediaPlayHysteresis(current: false, fraction: 0),
        isFalse,
        reason: '完全不可见',
      );
    });

    test('fraction=0.3 仍不应转可见（在迟滞区间）', () {
      expect(
        mediaPlayHysteresis(current: false, fraction: 0.3),
        isFalse,
        reason: '0.1~0.5 区间保持不可见态',
      );
    });

    test('fraction=0.5 边界不转可见（严格大于）', () {
      expect(
        mediaPlayHysteresis(current: false, fraction: 0.5),
        isFalse,
        reason: 'play 阈值是严格 >',
      );
    });

    test('fraction=0.6 应转可见', () {
      expect(
        mediaPlayHysteresis(current: false, fraction: 0.6),
        isTrue,
      );
    });

    test('fraction=1.0 完全可见', () {
      expect(
        mediaPlayHysteresis(current: false, fraction: 1.0),
        isTrue,
      );
    });
  });

  group('mediaPlayHysteresis - 可见 → 不可见（跌过 pause 阈值 0.1）', () {
    test('fraction=1.0 保持可见', () {
      expect(
        mediaPlayHysteresis(current: true, fraction: 1.0),
        isTrue,
      );
    });

    test('fraction=0.3 保持可见（在迟滞区间）', () {
      expect(
        mediaPlayHysteresis(current: true, fraction: 0.3),
        isTrue,
        reason: '0.1~0.5 区间保持可见态，这就是防抖的核心',
      );
    });

    test('fraction=0.1 边界转不可见（严格大于才保持）', () {
      expect(
        mediaPlayHysteresis(current: true, fraction: 0.1),
        isFalse,
        reason: 'pause 阈值：fraction > 0.1 才保持可见，等于 0.1 即不可见',
      );
    });

    test('fraction=0.05 转不可见', () {
      expect(
        mediaPlayHysteresis(current: true, fraction: 0.05),
        isFalse,
      );
    });

    test('fraction=0 完全滚出 → 不可见', () {
      expect(
        mediaPlayHysteresis(current: true, fraction: 0),
        isFalse,
        reason: '滚出视野，触发离屏 pause',
      );
    });
  });

  group('mediaPlayHysteresis - 迟滞区间（0.1~0.5）保持上一态', () {
    // 这是防抖的灵魂：在区间内，结果只取决于 current，不取决于 fraction。
    for (final f in [0.11, 0.2, 0.3, 0.4, 0.49]) {
      test('fraction=$f 时保持 current 态', () {
        // current=false → false
        expect(
          mediaPlayHysteresis(current: false, fraction: f),
          isFalse,
        );
        // current=true → true
        expect(
          mediaPlayHysteresis(current: true, fraction: f),
          isTrue,
        );
      });
    }
  });

  group('mediaPlayHysteresis - 自定义阈值', () {
    test('可覆盖默认阈值（如严格单阈值 0.5/0.5）', () {
      // 当 play=pause=0.5 时退化为单阈值（无迟滞）
      expect(
        mediaPlayHysteresis(
          current: true,
          fraction: 0.3,
          playThreshold: 0.5,
          pauseThreshold: 0.5,
        ),
        isFalse,
        reason: '单阈值模式下 0.3 < 0.5 → 不可见',
      );
    });
  });

  group('mediaPlayHysteresis - 端到端滚动序列', () {
    test('模拟一次"滚入→停留→滚出"的 fraction 序列', () {
      // 模拟 ListView 卡片从下方滚入、居中、再滚出顶部
      final sequence = [
        (0.0, false), // 完全在屏外（初始不可见）
        (0.2, false), // 露头，但 < 0.5，仍不可见
        (0.6, true), // 超过一半 → 转可见，开始播放
        (1.0, true), // 完全居中
        (0.7, true), // 开始滚出
        (0.4, true), // 进入迟滞区间，保持可见（防抖，避免误停）
        (0.2, true), // 仍在区间内，保持播放
        (0.08, false), // 跌破 0.1 → 离屏 pause
        (0.0, false), // 完全滚出
      ];
      var current = false;
      for (final (fraction, expected) in sequence) {
        current = mediaPlayHysteresis(current: current, fraction: fraction);
        expect(
          current,
          expected,
          reason: 'fraction=$fraction 后状态应为 $expected',
        );
      }
    });
  });

  // ===========================================================================
  // mediaVideoPlayCommand：shouldPlay ↔ isPlaying → 指令
  // ===========================================================================
  group('mediaVideoPlayCommand - 状态转换', () {
    test('shouldPlay=true 且未在播放 → play', () {
      expect(
        mediaVideoPlayCommand(shouldPlay: true, isPlaying: false),
        VideoPlayCommand.play,
      );
    });

    test('shouldPlay=false 且正在播放 → pause', () {
      expect(
        mediaVideoPlayCommand(shouldPlay: false, isPlaying: true),
        VideoPlayCommand.pause,
      );
    });
  });

  group('mediaVideoPlayCommand - 防重复调用（核心契约）', () {
    test('shouldPlay=true 且已在播放 → none（不重复 play）', () {
      // didUpdateWidget 多次触发时，不应反复调用 controller.play()
      expect(
        mediaVideoPlayCommand(shouldPlay: true, isPlaying: true),
        VideoPlayCommand.none,
        reason: '状态已一致，避免重复 play 抖动',
      );
    });

    test('shouldPlay=false 且已暂停 → none（不重复 pause）', () {
      expect(
        mediaVideoPlayCommand(shouldPlay: false, isPlaying: false),
        VideoPlayCommand.none,
        reason: '离屏后多次回调不应反复 pause',
      );
    });
  });

  group('mediaVideoPlayCommand - 离屏 pause 行为序列', () {
    test('模拟"可见播放 → 滚出 → 回滚"的指令序列', () {
      // isPlaying 初始 false，可见后 play，播放中滚出 pause，回滚再 play
      final steps = <(bool shouldPlay, bool isPlaying, VideoPlayCommand cmd)>[
        (true, false, VideoPlayCommand.play), // 进入可见 → 播放
        (true, true, VideoPlayCommand.none), // 播放中，状态稳定
        (false, true, VideoPlayCommand.pause), // 滚出视野 → 离屏 pause
        (false, false, VideoPlayCommand.none), // 已暂停，不再重复
        (true, false, VideoPlayCommand.play), // 回滚入视野 → 继续播放
      ];
      for (final (shouldPlay, isPlaying, expected) in steps) {
        expect(
          mediaVideoPlayCommand(
            shouldPlay: shouldPlay,
            isPlaying: isPlaying,
          ),
          expected,
          reason: 'shouldPlay=$shouldPlay isPlaying=$isPlaying',
        );
      }
    });
  });
}
