/// ContentSanitizer 内容净化器单元测试
///
/// 验证 markdown 标记剥离规则：
/// - 代码块围栏
/// - 行内代码
/// - 标题标记
/// - 粗体/斜体
/// - 引用标记
/// - 分隔线
/// - 空行压缩
/// - 普通文本不误伤
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/utils/content_sanitizer_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/utils/content_sanitizer.dart';

void main() {
  group('ContentSanitizer', () {
    // ═══ 粗体/斜体 ═══

    test('去除 **粗体** 标记', () {
      expect(ContentSanitizer.sanitize('**hello world**'), 'hello world');
    });

    test('去除 __粗体__ 标记', () {
      expect(ContentSanitizer.sanitize('__hello world__'), 'hello world');
    });

    test('去除 *斜体* 标记', () {
      expect(ContentSanitizer.sanitize('*hello world*'), 'hello world');
    });

    test('去除 _斜体_ 标记', () {
      expect(ContentSanitizer.sanitize('_hello world_'), 'hello world');
    });

    test('混合粗体和斜体', () {
      expect(
        ContentSanitizer.sanitize('这是**粗体**和*斜体*的混合'),
        '这是粗体和斜体的混合',
      );
    });

    // ═══ 标题 ═══

    test('去除 # 一级标题', () {
      expect(ContentSanitizer.sanitize('# 第一章'), '第一章');
    });

    test('去除 ## 二级标题', () {
      expect(ContentSanitizer.sanitize('## 第一节'), '第一节');
    });

    test('去除 ### 三级标题', () {
      expect(ContentSanitizer.sanitize('### 场景描写'), '场景描写');
    });

    test('标题后换行正文保留', () {
      expect(ContentSanitizer.sanitize('# 标题\n正文内容'), '标题\n正文内容');
    });

    // ═══ 代码块 ═══

    test('去除代码块围栏', () {
      expect(ContentSanitizer.sanitize('```\ncode here\n```'), 'code here');
    });

    test('去除带语言标记的代码块围栏', () {
      expect(ContentSanitizer.sanitize('```dart\ncode here\n```'), 'code here');
    });

    // ═══ 行内代码 ═══

    test('去除行内代码反引号', () {
      expect(ContentSanitizer.sanitize('使用 `print()` 函数'), '使用 print() 函数');
    });

    // ═══ 引用 ═══

    test('去除 > 引用标记', () {
      expect(ContentSanitizer.sanitize('> 引用文字'), '引用文字');
    });

    test('去除多行引用标记', () {
      expect(
        ContentSanitizer.sanitize('> 第一行\n> 第二行'),
        '第一行\n第二行',
      );
    });

    // ═══ 分隔线 ═══

    test('去除 --- 分隔线', () {
      expect(ContentSanitizer.sanitize('上文\n---\n下文'), '上文\n下文');
    });

    test('去除 *** 分隔线', () {
      expect(ContentSanitizer.sanitize('上文\n***\n下文'), '上文\n下文');
    });

    // ═══ 空行压缩 ═══

    test('压缩连续空行', () {
      expect(ContentSanitizer.sanitize('段落1\n\n\n\n段落2'), '段落1\n\n段落2');
    });

    // ═══ 不误伤 ═══

    test('普通文本不变', () {
      expect(ContentSanitizer.sanitize('这是一段普通文本'), '这是一段普通文本');
    });

    test('含中文标点不变', () {
      expect(ContentSanitizer.sanitize('他说："你好！"'), '他说："你好！"');
    });

    test('数字和英文不变', () {
      expect(ContentSanitizer.sanitize('第3章 ABC 123'), '第3章 ABC 123');
    });

    test('段落换行保留', () {
      expect(ContentSanitizer.sanitize('段落1\n\n段落2'), '段落1\n\n段落2');
    });

    // ═══ 综合场景 ═══

    test('综合: LLM 典型输出', () {
      const input = '# 第三章\n\n**李明**走进了房间。\n\n> "你好。"\n\n他*叹了口气*。';
      const expected = '第三章\n\n李明走进了房间。\n\n"你好。"\n\n他叹了口气。';
      expect(ContentSanitizer.sanitize(input), expected);
    });
  });
}
