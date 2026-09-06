import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/prompt_history.dart';
import 'package:novel_app/models/saved_tag_group.dart';

/// PromptHistory 模型 - tagGroups 字段测试
///
/// 验证 PromptHistory 模型的 tagGroups 字段：
/// - 默认值（空列表）
/// - toMap / fromMap 正确序列化
/// - 空 tag_group_ids 兼容（旧数据）
/// - copyWith 正确处理 tagGroups
void main() {
  group('PromptHistory - tagGroups 字段', () {
    final now = DateTime(2026, 6, 14, 10, 0);
    const testText = '请写一段紧张的对峙场景';

    test('默认 tagGroups 为空列表', () {
      final history = PromptHistory(
        promptText: testText,
        createdAt: now,
        updatedAt: now,
      );

      expect(history.tagGroups, isEmpty);
    });

    test('toMap 正确序列化 tagGroups 为 JSON', () {
      final history = PromptHistory(
        promptText: testText,
        createdAt: now,
        updatedAt: now,
        tagGroups: const [
          SavedTagGroup(categoryId: 1, name: '紧张对峙'),
          SavedTagGroup(categoryId: 2, name: '心理活动'),
        ],
      );

      final map = history.toMap();

      expect(map['tag_group_ids'], isA<String>());
      expect(map['tag_group_ids'], contains('"categoryId":1'));
      expect(map['tag_group_ids'], contains('"name":"紧张对峙"'));
      expect(map['tag_group_ids'], contains('"categoryId":2'));
      expect(map['tag_group_ids'], contains('"name":"心理活动"'));
    });

    test('fromMap 正确反序列化 tagGroups', () {
      final map = {
        'id': 1,
        'prompt_text': testText,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'tag_group_ids': '[{"categoryId":1,"name":"紧张对峙"},{"categoryId":3,"name":"动作描写"}]',
      };

      final history = PromptHistory.fromMap(map);

      expect(history.tagGroups, hasLength(2));
      expect(history.tagGroups[0].categoryId, 1);
      expect(history.tagGroups[0].name, '紧张对峙');
      expect(history.tagGroups[1].categoryId, 3);
      expect(history.tagGroups[1].name, '动作描写');
    });

    test('fromMap 兼容 null tag_group_ids（旧数据）', () {
      final map = {
        'id': 1,
        'prompt_text': testText,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        // 没有 tag_group_ids 字段
      };

      final history = PromptHistory.fromMap(map);

      expect(history.tagGroups, isEmpty);
    });

    test('fromMap 兼容空字符串 tag_group_ids', () {
      final map = {
        'id': 1,
        'prompt_text': testText,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'tag_group_ids': '',
      };

      final history = PromptHistory.fromMap(map);

      expect(history.tagGroups, isEmpty);
    });

    test('fromMap 兼容非法 JSON（不崩溃）', () {
      final map = {
        'id': 1,
        'prompt_text': testText,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'tag_group_ids': 'not-valid-json',
      };

      final history = PromptHistory.fromMap(map);

      expect(history.tagGroups, isEmpty);
    });

    test('copyWith 正确复制 tagGroups', () {
      final original = PromptHistory(
        id: 1,
        promptText: testText,
        createdAt: now,
        updatedAt: now,
        tagGroups: const [
          SavedTagGroup(categoryId: 1, name: '紧张对峙'),
        ],
      );

      final copied = original.copyWith(
        promptText: '新文本',
        tagGroups: const [
          SavedTagGroup(categoryId: 2, name: '心理活动'),
          SavedTagGroup(categoryId: 3, name: '动作描写'),
        ],
      );

      expect(copied.id, 1);
      expect(copied.promptText, '新文本');
      expect(copied.tagGroups, hasLength(2));
      expect(copied.tagGroups[0].name, '心理活动');
    });

    test('copyWith 不传 tagGroups 时保持原值', () {
      final original = PromptHistory(
        id: 1,
        promptText: testText,
        createdAt: now,
        updatedAt: now,
        tagGroups: const [
          SavedTagGroup(categoryId: 1, name: '紧张对峙'),
        ],
      );

      final copied = original.copyWith(promptText: '新文本');

      expect(copied.tagGroups, hasLength(1));
      expect(copied.tagGroups[0].name, '紧张对峙');
    });

    test('toMap 空 tagGroups 序列化为 "[]"', () {
      final history = PromptHistory(
        promptText: testText,
        createdAt: now,
        updatedAt: now,
      );

      final map = history.toMap();

      expect(map['tag_group_ids'], '[]');
    });
  });
}
