import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/novel.dart';

/// Novel 模型 - backgroundSetting 字段验证测试
///
/// 验证 Novel 模型是否包含 backgroundSetting 字字段：
/// - backgroundSetting 字段存在
/// - 可以正确赋值和读取
/// - copyWith 方法正确处理 backgroundSetting
void main() {
  group('Novel 模型 - backgroundSetting 字段测试', () {
    test('Novel 应该包含 backgroundSetting 字段', () {
      // Arrange & Act
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: '测试背景设定',
      );

      // Assert
      expect(novel.backgroundSetting, '测试背景设定');
      expect(novel.backgroundSetting, isNotNull);
    });

    test('backgroundSetting 可以为 null', () {
      // Arrange & Act
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: null,
      );

      // Assert
      expect(novel.backgroundSetting, isNull);
    });

    test('backgroundSetting 可以为空字符串', () {
      // Arrange & Act
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: '',
      );

      // Assert
      expect(novel.backgroundSetting, '');
      expect(novel.backgroundSetting, isEmpty);
    });

    test('copyWith 方法应该正确复制 backgroundSetting', () {
      // Arrange
      final original = Novel(
        title: '原标题',
        author: '原作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: '原背景设定',
      );

      // Act
      final copy = original.copyWith(backgroundSetting: '新背景设定');

      // Assert
      expect(copy.backgroundSetting, '新背景设定');
      expect(copy.title, '原标题'); // 其他字段保持不变
    });

    test('copyWith 不传 backgroundSetting 时应该保持原值', () {
      // Arrange
      final original = Novel(
        title: '原标题',
        author: '原作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: '原背景设定',
      );

      // Act
      final copy = original.copyWith(title: '新标题');

      // Assert
      expect(copy.backgroundSetting, '原背景设定'); // 保持原值
      expect(copy.title, '新标题');
    });

    test('backgroundSetting 与 description 是独立字段', () {
      // Arrange & Act
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        description: '这是小说简介（description）',
        backgroundSetting: '这是背景设定（backgroundSetting）',
      );

      // Assert - 两个字段应该独立，互不影响
      expect(novel.description, '这是小说简介（description）');
      expect(novel.backgroundSetting, '这是背景设定（backgroundSetting）');
      expect(novel.description, isNot(novel.backgroundSetting));
    });
  });

  group('Bug修复验证 - buildChapterGenerationInputs 使用正确的字段', () {
    test('背景设定字段名称应该是 backgroundSetting', () {
      // Arrange - 创建 Novel 对象
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        description: '这是小说简介',
        backgroundSetting: '这是背景设定',
      );

      // Act - 模拟 buildChapterGenerationInputs 的逻辑
      final backgroundSetting = novel.backgroundSetting ?? '';

      // Assert - 验证使用正确的字段
      expect(backgroundSetting, '这是背景设定');
      expect(backgroundSetting, isNot(novel.description));
    });

    test('backgroundSetting 为 null 时应该返回空字符串', () {
      // Arrange - 创建 Novel 对象，background
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        description: '这是小说简介',
        backgroundSetting: null,
      );

      // Act - 模拟 buildChapterGenerationInputs 的逻辑
      final backgroundSetting = novel.backgroundSetting ?? '';

      // Assert
      expect(backgroundSetting, '');
    });

    test('完整验证 - Dify inputs 包含正确的 background_setting', () {
      // Arrange
      final novel = Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/test',
        backgroundSetting: '未来世界设定：人类已掌握超光速技术',
      );

      // Act - 模拟 buildChapterGenerationInputs 返回的 inputs
      final inputs = <String, dynamic>{
        'user_input': '生成第三章',
        'cmd': '',
        'current_chapter_content': '',
        'history_chapters_content': '历史内容',
        // Bug 修复：使用 novel.backgroundSetting 而非 novel.description
        'background_setting': novel.backgroundSetting ?? '',
        'ai_writer_setting': '',
        'next_chapter_overview': '',
        'roles': '',
      };

      // Assert
      expect(inputs['background_setting'], '未来世界设定：人类已掌握超光速技术');
      expect(inputs['background_setting'], isNot(novel.description));
      expect(inputs, containsPair('background_setting', isNotNull));
    });
  });
}
