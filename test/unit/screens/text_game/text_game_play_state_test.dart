/// 游玩页状态语义测试（纯状态，无 provider/DB 依赖）
///
/// 重点锁住 isEmptyGame（扉页判定）：首回合失败时 error 非空也必须保留
/// 扉页/开始入口，否则玩家掉进一片空白的剧情列表。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';
import 'package:novel_app/screens/text_game/text_game_play_controller.dart';

void main() {
  group('isEmptyGame（未开始的新游戏 → 扉页/开始入口）', () {
    test('空链且空闲 → 扉页', () {
      expect(
        const TextGamePlayState(initializing: false).isEmptyGame,
        isTrue,
      );
    });

    test('首回合失败（error 非空）→ 仍是扉页（按钮兼作重试）', () {
      expect(
        const TextGamePlayState(initializing: false, error: '网络失败')
            .isEmptyGame,
        isTrue,
      );
    });

    test('加载中 / 运行中 / 已有内容 → 非扉页', () {
      expect(const TextGamePlayState().isEmptyGame, isFalse, reason: '初始化中');
      expect(
        const TextGamePlayState(initializing: false, agentRunning: true)
            .isEmptyGame,
        isFalse,
        reason: '回合运行中走剧情流',
      );
      expect(
        const TextGamePlayState(
          initializing: false,
          transcript: [GameNarration('雨夜，你在城门口醒来。')],
        ).isEmptyGame,
        isFalse,
        reason: '已有定稿剧情',
      );
    });
  });
}
