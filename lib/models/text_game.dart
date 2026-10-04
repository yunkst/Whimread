/// 文字游戏（text_games 表）
///
/// 一个游戏一行：剧情历史复用 chat_sessions / chat_messages（chatSessionId
/// 关联），消息链是剧情的真理源。**必须绑定小说**（sourceNovelId 指向
/// bookshelf.id）：角色卡（含头像/说话风格/近况）共享小说的 characters 表，
/// settings_json 只存游戏侧数据（开场/规则/参战名单/玩家角色指向）。
library;

import 'dart:convert';

/// 游戏状态
enum TextGameStatus {
  active,
  finished,
  abandoned;

  static TextGameStatus fromName(String? name) {
    return TextGameStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => TextGameStatus.active,
    );
  }
}

/// 场景图生成策略
enum GameImagePolicy {
  /// agent 自行判断关键场景时调用 create_scene_image
  auto,

  /// 仅玩家点「生成插图」按钮时生成（agent 工具面不含生图）
  manual;

  static GameImagePolicy fromName(String? name) {
    return GameImagePolicy.values.firstWhere(
      (p) => p.name == name,
      orElse: () => GameImagePolicy.auto,
    );
  }
}

/// 游戏规则（叙事风格 / 内容边界 / 选项数量 / 生图策略）
class GameRules {
  final String narrativeStyle;
  final String contentBoundary;

  /// 每回合选项数量（2-4）
  final int choicesCount;
  final GameImagePolicy imagePolicy;

  const GameRules({
    this.narrativeStyle = '',
    this.contentBoundary = '',
    this.choicesCount = 3,
    this.imagePolicy = GameImagePolicy.auto,
  });

  Map<String, dynamic> toJson() => {
        'narrativeStyle': narrativeStyle,
        'contentBoundary': contentBoundary,
        'choicesCount': choicesCount,
        'imagePolicy': imagePolicy.name,
      };

  factory GameRules.fromJson(Map<String, dynamic> json) => GameRules(
        narrativeStyle: json['narrativeStyle'] as String? ?? '',
        contentBoundary: json['contentBoundary'] as String? ?? '',
        choicesCount: (json['choicesCount'] as num?)?.toInt() ?? 3,
        imagePolicy: GameImagePolicy.fromName(json['imagePolicy'] as String?),
      );
}

/// 游戏设定（settings_json 的结构化视图）
///
/// 角色卡共享小说 characters 表，不在此快照拷贝：
/// - [characterIds] 参战名单（characters.id；创建时缺省取绑定小说全部
///   角色卡，可显式圈定子集，游戏中 GM 建新角色会自动追加）；
///   动态上下文只渲染名单内角色
/// - [playerCharacterId] 玩家角色卡 id（characters 表一行，其 currentState
///   即玩家当前状态，同样进版本管理）
/// - [coreExperience] 核心体验（用户想获得的游玩感受，GM 演出的最高准则；
///   创建时必问，用户可在设定编辑页手动修改）
/// - [worldNotes] 世界与剧情线状态条目（任务/势力动向/未解悬念，一行一条；
///   游戏侧数据，不进角色卡版本管理）
/// - [worldview] 为空时回退来源小说的 backgroundSetting
class GameSettings {
  final String worldview;
  final String opening;
  final List<int> characterIds;

  /// 玩家角色卡 id（characters.id；未指定 = 未设置玩家角色）
  final int? playerCharacterId;

  /// 核心体验：节奏快慢/爽感来源/描写密度/叙事人称/挫败感等偏好，写成对
  /// GM 的正向演出指令；空 = 未设定（GM 按静态协议的通用节奏演出）
  final String coreExperience;
  final GameRules rules;

  /// 世界与剧情线条目（update_game_state target="world" 或手动编辑维护）
  final List<String> worldNotes;

  const GameSettings({
    this.worldview = '',
    this.opening = '',
    this.characterIds = const [],
    this.playerCharacterId,
    this.coreExperience = '',
    this.rules = const GameRules(),
    this.worldNotes = const [],
  });

  Map<String, dynamic> toJson() => {
        'worldview': worldview,
        'opening': opening,
        'characterIds': characterIds,
        if (playerCharacterId != null) 'playerCharacterId': playerCharacterId,
        if (coreExperience.isNotEmpty) 'coreExperience': coreExperience,
        'rules': rules.toJson(),
        if (worldNotes.isNotEmpty) 'worldNotes': worldNotes,
      };

  factory GameSettings.fromJson(Map<String, dynamic> json) => GameSettings(
        worldview: json['worldview'] as String? ?? '',
        opening: json['opening'] as String? ?? '',
        characterIds: (json['characterIds'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
        playerCharacterId: (json['playerCharacterId'] as num?)?.toInt(),
        coreExperience: json['coreExperience'] as String? ?? '',
        rules: GameRules.fromJson(
            json['rules'] as Map<String, dynamic>? ?? const {}),
        worldNotes: (json['worldNotes'] as List<dynamic>? ?? const [])
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(),
      );

  /// 解析失败时回退到空设定，不抛异常——settings_json 是 agent 工具写入的，
  /// 容错比崩溃好。
  factory GameSettings.fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return GameSettings.fromJson(decoded);
      }
    } catch (_) {
      // fall through
    }
    return const GameSettings();
  }

  /// 追加参战角色（去重），返回新设定
  GameSettings withCharacter(int characterId) {
    if (characterIds.contains(characterId)) return this;
    return copyWith(characterIds: [...characterIds, characterId]);
  }

  GameSettings copyWith({
    String? worldview,
    String? opening,
    List<int>? characterIds,
    int? playerCharacterId,
    String? coreExperience,
    GameRules? rules,
    List<String>? worldNotes,
  }) {
    return GameSettings(
      worldview: worldview ?? this.worldview,
      opening: opening ?? this.opening,
      characterIds: characterIds ?? this.characterIds,
      playerCharacterId: playerCharacterId ?? this.playerCharacterId,
      coreExperience: coreExperience ?? this.coreExperience,
      rules: rules ?? this.rules,
      worldNotes: worldNotes ?? this.worldNotes,
    );
  }

  String toJsonString() => jsonEncode(toJson());
}

/// 游戏实例（text_games 行）
class TextGame {
  final int? id;
  final String title;

  /// 来源小说的 bookshelf.id（必填：游戏必须绑定小说以共享角色卡）
  final int? sourceNovelId;

  /// 来源小说标题（快照，小说删除后仍可显示）
  final String? sourceNovelTitle;
  final GameSettings settings;
  final TextGameStatus status;

  /// 剧情历史所在的 chat_sessions.id
  final int chatSessionId;
  final String? coverMediaId;
  final DateTime? lastPlayedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TextGame({
    this.id,
    required this.title,
    this.sourceNovelId,
    this.sourceNovelTitle,
    required this.settings,
    this.status = TextGameStatus.active,
    required this.chatSessionId,
    this.coverMediaId,
    this.lastPlayedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        // 列保留供 schema 稳定；统一模型下恒为 novel
        'sourceType': 'novel',
        'sourceNovelId': sourceNovelId,
        'sourceNovelTitle': sourceNovelTitle,
        'settingsJson': settings.toJsonString(),
        'status': status.name,
        'chatSessionId': chatSessionId,
        'coverMediaId': coverMediaId,
        'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory TextGame.fromMap(Map<String, dynamic> map) {
    DateTime fromMs(Object? v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v)
        : DateTime.now();
    return TextGame(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      sourceNovelId: map['sourceNovelId'] as int?,
      sourceNovelTitle: map['sourceNovelTitle'] as String?,
      settings:
          GameSettings.fromJsonString(map['settingsJson'] as String? ?? ''),
      status: TextGameStatus.fromName(map['status'] as String?),
      chatSessionId: map['chatSessionId'] as int? ?? 0,
      coverMediaId: map['coverMediaId'] as String?,
      lastPlayedAt:
          map['lastPlayedAt'] is int ? fromMs(map['lastPlayedAt']) : null,
      createdAt: fromMs(map['createdAt']),
      updatedAt: fromMs(map['updatedAt']),
    );
  }

  TextGame copyWith({
    int? id,
    String? title,
    int? sourceNovelId,
    String? sourceNovelTitle,
    GameSettings? settings,
    TextGameStatus? status,
    int? chatSessionId,
    String? coverMediaId,
    DateTime? lastPlayedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TextGame(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceNovelId: sourceNovelId ?? this.sourceNovelId,
      sourceNovelTitle: sourceNovelTitle ?? this.sourceNovelTitle,
      settings: settings ?? this.settings,
      status: status ?? this.status,
      chatSessionId: chatSessionId ?? this.chatSessionId,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'TextGame(id: $id, title: $title, status: ${status.name}, '
      'chatSessionId: $chatSessionId)';
}
