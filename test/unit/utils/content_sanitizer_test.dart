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

  group('detectJsonContamination — JSON 污染检测', () {
    // 反馈 #16「llm替换文字，出现错乱」实测样本（feedback llm_logs seq=14）：
    // 模型生成入参时 JSON 结构错乱，newString 值吞进了工具调用的结构尾巴。
    // 这是 embedded_key_value 形态——正文开头干净、尾部带回声，整体不是
    // 合法 JSON，也无围栏，规则①②③均拦不住，只有规则④能拦。
    const seq14Sample =
        '等了大概十分钟。\n许曼璃终于姗姗来迟。\n"不好意思啊，陈北，我迟到了。"\n'
        '许曼璃抱着陈北的胳膊，一脸微笑的往店里走去。\n她柔软的身子紧紧贴着'
        '陈北的手臂，让陈北心头微微一荡。", "oldString": "等了大概十分钟。\n'
        '许曼璃终于姗姗来迟。", "position": 79}';

    test('规则④：反馈 #16 实际样本（embedded_key_value）→ 拦截', () {
      expect(
        ContentSanitizer.detectJsonContamination(seq14Sample),
        'embedded_key_value',
      );
    });

    test('规则①：整体即 JSON 对象 → 拦截', () {
      expect(
        ContentSanitizer.detectJsonContamination('{"title": "第3章", "content": "正文"}'),
        'whole_string_json',
      );
    });

    test('规则①：整体即 JSON 数组 → 拦截', () {
      expect(
        ContentSanitizer.detectJsonContamination('[{"p": "第一段"}, {"p": "第二段"}]'),
        'whole_string_json',
      );
    });

    test('规则②：```json 围栏内是 JSON → 拦截', () {
      const input = '正文开头。\n```json\n{"oldString": "a", "newString": "b"}\n```\n正文结尾。';
      expect(ContentSanitizer.detectJsonContamination(input), 'fenced_json');
    });

    test('规则③：独立行工具调用回声（≥2 已知键）→ 拦截', () {
      const input = '正文开头。\n{"position": 79, "oldString": "原文", "newString": "新文"}\n正文结尾。';
      expect(ContentSanitizer.detectJsonContamination(input), 'tool_call_echo');
    });

    test('误伤防线：含冒号引号换行的正常对话 → 放行', () {
      const input = '"不好意思啊，陈北，我迟到了，让你久等了。"\n他说：没事，我们走。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('误伤防线：正文内嵌非工具键的 JSON（程序员题材）→ 放行', () {
      const input = '他在白板上写下 {"a": 1, "b": 2} 然后转身。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('误伤防线：独立行 JSON 但无已知工具键 → 放行', () {
      const input = '配置如下\n{"host": "localhost", "port": 8080}\n完毕。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('误伤防线：```text 围栏里的散文 → 放行', () {
      const input = '他念出了屏幕上的话。\n```text\n这不是一段 JSON，只是一句话。\n```\n念完他笑了。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('误伤防线：``` 围栏里的非 JSON 代码 → 放行', () {
      const input = '代码如下。\n```\nprint("hello world")\n```\n运行成功。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('误伤防线：中文引号对话中的逗号冒号 → 放行', () {
      const input = '“你好，”她说，“这是“position”：一个词。”';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });

    test('纯正文（多段落）→ 放行', () {
      const input = '第一段。\n\n第二段，有标点。"引号"\n\n第三段。';
      expect(ContentSanitizer.detectJsonContamination(input), isNull);
    });
  });
}
