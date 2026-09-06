import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/theme/app_colors.dart';

void main() {
  /// 晨读书馆重做依赖的暖调 token：亮/暗都必须非 null 且不同值（防回归）。
  /// 冷调遗留 token（chatRoleBubble/chatUserBubble/...）不纳入断言，待清理。
  /// chat 文本/分割线已并入 ink/inkSoft/divider（Phase 2 合并），不再单独断言。
  final warmTokens = <String, Function(AppColors)>{
    'paper': (c) => c.paper,
    'ink': (c) => c.ink,
    'inkSoft': (c) => c.inkSoft,
    'chatButtonPrimary': (c) => c.chatButtonPrimary,
    'chatInputBackground': (c) => c.chatInputBackground,
    'chatHintText': (c) => c.chatHintText,
    'error': (c) => c.error,
  };

  for (final entry in warmTokens.entries) {
    test('${entry.key} 亮/暗均非 null 且不同值', () {
      final light = entry.value(AppColors.light);
      final dark = entry.value(AppColors.dark);
      expect(light, isNotNull, reason: '${entry.key} light 为 null');
      expect(dark, isNotNull, reason: '${entry.key} dark 为 null');
      expect(light, isNot(equals(dark)),
          reason: '${entry.key} 亮/暗同值（应不同明度）');
    });
  }
}
