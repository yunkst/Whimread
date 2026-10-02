/// 文字游戏 Provider
///
/// 手写 Provider（与 chat_session_providers / scenario_sessions_provider
/// 同风格，避免引入 build_runner）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/text_game.dart';
import '../../services/text_game/text_game_image_service.dart';
import 'database_providers.dart';
import 'service_providers.dart' show preferencesServiceProvider;

/// 场景图异步生图服务（App 生命周期单例）
final textGameImageServiceProvider = Provider<TextGameImageService>((ref) {
  final service = TextGameImageService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// 文字游戏列表状态（管理页数据源）
class TextGamesState {
  final List<TextGame> games;
  final bool isLoading;
  final String? error;

  const TextGamesState({
    this.games = const [],
    this.isLoading = false,
    this.error,
  });

  TextGamesState copyWith({
    List<TextGame>? games,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return TextGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 文字游戏列表 Notifier
///
/// 创建（写作助手 create_text_game 工具）/ 删除后 invalidate 本 provider
/// 刷新；列表按 lastPlayedAt DESC 排序（repo 保证）。
class TextGamesNotifier extends StateNotifier<TextGamesState> {
  final Ref _ref;

  TextGamesNotifier(this._ref) : super(const TextGamesState(isLoading: true)) {
    _reload();
  }

  Future<void> _reload() async {
    try {
      final games = await _ref.read(textGameRepositoryProvider).listAll();
      if (!mounted) return;
      state = state.copyWith(games: games, isLoading: false, clearError: true);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 手动刷新（管理页下拉/删除/创建后）
  Future<void> refresh() => _reload();
}

final textGamesProvider =
    StateNotifierProvider<TextGamesNotifier, TextGamesState>((ref) {
  return TextGamesNotifier(ref);
});

/// "GM 思考"开关（游玩页显示思维链与幕后动作，SharedPreferences 持久化）
///
/// 纯 UI 展示偏好：思维链不落库不进消息链，开启只影响实时过程展示，
/// 离开页面/回合结束后历史不可回看。
class GmThinkingVisibleNotifier extends StateNotifier<bool> {
  static const _key = 'text_game.gm_thinking_visible';

  GmThinkingVisibleNotifier(this._ref) : super(false) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final value = await _ref
          .read(preferencesServiceProvider)
          .getBool(_key, defaultValue: false);
      if (!mounted) return;
      state = value;
    } catch (_) {
      // 读取失败保持默认关闭
    }
  }

  Future<void> toggle() async {
    final next = !state;
    state = next;
    try {
      await _ref.read(preferencesServiceProvider).setBool(_key, next);
    } catch (_) {
      // 持久化失败不影响本次会话内的展示
    }
  }
}

final gmThinkingVisibleProvider =
    StateNotifierProvider<GmThinkingVisibleNotifier, bool>((ref) {
  return GmThinkingVisibleNotifier(ref);
});
