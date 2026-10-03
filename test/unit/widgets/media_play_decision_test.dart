/// MediaView 可见性决策单元测试
///
/// 覆盖纯函数 [mediaPlayHysteresis]：可见性双阈值迟滞（0.1/0.5），
/// 防 fling 抖动。零依赖、可单测。
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
}
