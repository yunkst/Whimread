import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/saved_tag_group.dart';
import 'package:novel_app/models/tag_group.dart';

/// SavedTagGroup 模型测试
///
/// 验证 SavedTagGroup 快照模型的 JSON 序列化与 TagGroup 转换。
void main() {
  group('SavedTagGroup - JSON 序列化', () {
    test('toJson 输出正确字段', () {
      const saved = SavedTagGroup(categoryId: 1, name: '紧张对峙');

      final json = saved.toJson();

      expect(json['categoryId'], 1);
      expect(json['name'], '紧张对峙');
    });

    test('fromJson 正确解析字段', () {
      final json = {'categoryId': 3, 'name': '心理活动'};

      final saved = SavedTagGroup.fromJson(json);

      expect(saved.categoryId, 3);
      expect(saved.name, '心理活动');
    });

    test('JSON 往返一致性', () {
      const original = SavedTagGroup(categoryId: 5, name: '动作描写');

      final restored = SavedTagGroup.fromJson(original.toJson());

      expect(restored.categoryId, original.categoryId);
      expect(restored.name, original.name);
    });
  });

  group('SavedTagGroup - toTagGroup 转换', () {
    test('toTagGroup 返回 count=1, representativeId=0 的 TagGroup', () {
      const saved = SavedTagGroup(categoryId: 2, name: '场景');

      final tagGroup = saved.toTagGroup();

      expect(tagGroup.categoryId, 2);
      expect(tagGroup.name, '场景');
      expect(tagGroup.count, 1);
      expect(tagGroup.representativeId, 0);
    });

    test('toTagGroup 可被 PromptTagSelectorSheet 消费（不抛异常）', () {
      const saved = SavedTagGroup(categoryId: 1, name: '紧张对峙');

      // 模拟选择器 key 计算逻辑：${categoryId}:${name}
      final tagGroup = saved.toTagGroup();
      final key = '${tagGroup.categoryId}:${tagGroup.name}';

      expect(key, '1:紧张对峙');
    });
  });
}
