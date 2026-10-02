import 'dart:convert';

import 'character.dart';

/// 角色卡版本记录来源
///
/// 任何改卡路径都必须落一条来源，版本管理页据此展示「为什么创建这个版本」：
/// - [manual] 手动编辑（角色编辑页/头像设置等 UI 操作）
/// - [writingAgent] 小说写作助手 agent（create_character/update_character 工具）
/// - [textGame] 文字游戏场景（update_game_state / 游戏内 create_character）
/// - [rollback] 版本回滚动作本身（回滚也会追加一条新版本，历史保持线性）
class CharacterRevisionSource {
  static const String manual = 'manual';
  static const String writingAgent = 'writing_agent';
  static const String textGame = 'text_game';
  static const String rollback = 'rollback';

  /// 中文展示名（版本列表徽标用）
  static String label(String source) {
    switch (source) {
      case manual:
        return '手动编辑';
      case writingAgent:
        return '写作助手';
      case textGame:
        return '文字游戏';
      case rollback:
        return '版本回滚';
      default:
        return source;
    }
  }
}

/// 角色卡版本记录（character_revisions 表，v53）
///
/// 快照式版本管理：每次成功修改角色卡后写入**改后整卡快照**（而非 diff 或
/// 改前状态），因此「回滚到指定版本」= 把该版本的快照写回卡片。回滚本身
/// 也追加一条 [CharacterRevisionSource.rollback] 版本，历史保持 append-only
/// 线性日志，不做分支。
class CharacterRevision {
  final int? id;

  /// 所属角色卡 id（角色删除时版本记录级联清理）
  final int characterId;

  /// 改后整卡快照（Character.toMap 的 JSON；跨模型演进靠 fromMap 容错）
  final String snapshotJson;

  /// 修改来源，见 [CharacterRevisionSource]
  final String source;

  /// 来源定位（如「文字游戏《斗罗大陆》」「角色编辑页」），可为空
  final String? sourceRef;

  /// 修改原因（agent 回写时由工具参数给出的一句话，如「击败风笑天，获得玄重尺」）
  final String? reason;

  final DateTime createdAt;

  const CharacterRevision({
    this.id,
    required this.characterId,
    required this.snapshotJson,
    required this.source,
    this.sourceRef,
    this.reason,
    required this.createdAt,
  });

  /// 解析快照为角色卡。快照 JSON 损坏时返回 null（按不可回滚处理）。
  /// 跨模型演进容错：旧快照可能缺后来新增的字段，必填键缺失时补默认值。
  Character? parseSnapshot() {
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is Map) {
        final map = decoded.map((k, v) => MapEntry(k.toString(), v))
          ..putIfAbsent('novelUrl', () => '')
          ..putIfAbsent('name', () => '')
          ..putIfAbsent(
              'createdAt', () => DateTime.now().millisecondsSinceEpoch);
        return Character.fromMap(map);
      }
    } catch (_) {
      // 坏数据按无快照处理
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'characterId': characterId,
      'snapshotJson': snapshotJson,
      'source': source,
      'sourceRef': sourceRef,
      'reason': reason,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory CharacterRevision.fromMap(Map<String, dynamic> map) {
    return CharacterRevision(
      id: map['id']?.toInt(),
      characterId: map['characterId']?.toInt() ?? 0,
      snapshotJson: (map['snapshotJson'] as String?) ?? '',
      source: (map['source'] as String?) ?? CharacterRevisionSource.manual,
      sourceRef: map['sourceRef'] as String?,
      reason: map['reason'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
    );
  }

  CharacterRevision copyWith({
    int? id,
    int? characterId,
    String? snapshotJson,
    String? source,
    String? sourceRef,
    String? reason,
    DateTime? createdAt,
  }) {
    return CharacterRevision(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      source: source ?? this.source,
      sourceRef: sourceRef ?? this.sourceRef,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
