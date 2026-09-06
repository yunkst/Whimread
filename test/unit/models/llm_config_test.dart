/// LlmConfig 模型单元测试
///
/// 重点覆盖「复制」语义：
/// - LlmConfig.copyWith 用 `id ?? this.id` 处理可空字段，无法把 id 清空为 null。
///   历史上 `_duplicateConfig` 用 copyWith(id: null) 想生成新配置，结果新对象仍带原 id，
///   save() 走 update 分支，把原配置覆盖掉了（名字变 (副本)、默认状态丢失、无新行）。
/// - 正确入口是 [LlmConfig.duplicate]，它返回一个无 id 的副本。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/models/llm_config_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/llm_config.dart';

void main() {
  // 一条带 id 的「已落库」配置，作为复制/编辑的基线
  final base = LlmConfig(
    id: 7,
    name: 'DeepSeek',
    apiUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-xxx',
    model: 'deepseek-chat',
    isDefault: true,
    sortOrder: 3,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 2),
  );

  group('copyWith 可空字段陷阱（文档化回归约束）', () {
    test('copyWith(id: null) 无法清空 id —— 这正是复制 bug 的根因', () {
      // 这个断言记录「现状」：copyWith 不能用来生成「无 id」的副本。
      // 若哪天有人改 copyWith 让它能清空 id，本测试需要同步调整；
      // 在那之前，复制入口必须走 duplicate()。
      expect(
        base.copyWith(id: null).id,
        equals(7),
        reason: 'copyWith 用 id ?? this.id，传 null 会沿用原 id',
      );
    });
  });

  group('duplicate()', () {
    test('返回无 id 的副本（save 会走 insert 分支）', () {
      final copy = base.duplicate();

      expect(copy.id, isNull,
          reason: '副本必须无 id，否则 save 会覆盖原配置而不是新增');
    });

    test('name 加 "(副本)" 后缀', () {
      expect(base.duplicate().name, 'DeepSeek (副本)');
    });

    test('副本默认 isDefault=false，避免出现两个默认', () {
      expect(base.isDefault, isTrue, reason: '前置：原配置本身是默认');
      expect(base.duplicate().isDefault, isFalse);
    });

    test('继承连接信息与模型（复制目的就是省去重新填写）', () {
      final copy = base.duplicate();
      expect(copy.apiUrl, base.apiUrl);
      expect(copy.apiKey, base.apiKey);
      expect(copy.model, base.model);
    });

    test('不共享 id 引用 —— 原配置 id 不被改动', () {
      final copy = base.duplicate();
      expect(copy.id, isNull);
      expect(base.id, 7, reason: '原配置 id 必须保持不变');
    });
  });
}
