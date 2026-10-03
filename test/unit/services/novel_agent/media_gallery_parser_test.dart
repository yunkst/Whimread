/// parseMediaGallery 解析器单元测试
///
/// 验证 create_images / create_image_to_video 工具结果 JSON 的解析逻辑
/// （纯函数，无依赖）。覆盖：null、非法 JSON、success=false、images
/// 缺失/空、元素缺关键字段、完整有效数据。
///
/// 运行：
///   cd novel_app
///   flutter test test/unit/services/novel_agent/media_gallery_parser_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/media/media_types.dart';
import 'package:novel_app/widgets/agent_chat/media_gallery_card.dart';

void main() {
  group('parseMediaGallery - 边界返回 null', () {
    test('null 输入返回 null', () {
      expect(parseMediaGallery(null), isNull);
    });

    test('空字符串返回 null', () {
      expect(parseMediaGallery(''), isNull);
    });

    test('非 JSON 字符串返回 null', () {
      expect(parseMediaGallery('not a json'), isNull);
    });

    test('JSON 非 Map 返回 null', () {
      expect(parseMediaGallery('[1,2,3]'), isNull);
      expect(parseMediaGallery('"string"'), isNull);
      expect(parseMediaGallery('42'), isNull);
    });
  });

  group('parseMediaGallery - success 标志', () {
    test('success 缺失返回 null', () {
      expect(parseMediaGallery('{"images":[]}'), isNull);
    });

    test('success=false 返回 null（即使有 images）', () {
      final json = jsonEncode({
        'success': false,
        'error': 'backend_unavailable',
        'images': [
          {'mediaId': 'a'}
        ],
      });
      expect(parseMediaGallery(json), isNull);
    });

    test('success=true 但无 images 返回 null', () {
      expect(parseMediaGallery('{"success":true}'), isNull);
      expect(parseMediaGallery('{"success":true,"images":[]}'), isNull);
    });

    test('images 不是 List 返回 null', () {
      expect(
        parseMediaGallery('{"success":true,"images":{"a":1}}'),
        isNull,
      );
    });
  });

  group('parseMediaGallery - images 元素字段校验', () {
    test('图片元素缺 mediaId 时被跳过', () {
      final json = jsonEncode({
        'success': true,
        'images': [
          {'prompt': 'no id'}, // 无 mediaId
        ],
      });
      expect(parseMediaGallery(json), isNull, reason: '全部元素无效时应返回 null');
    });

    test('无效元素被跳过，有效元素保留', () {
      final json = jsonEncode({
        'success': true,
        'images': [
          {'mediaId': 'valid'},
          {'prompt': 'no id'}, // 缺 mediaId
          {'mediaId': 'also_valid', 'modelName': '写实1'},
        ],
      });
      final data = parseMediaGallery(json);
      expect(data, isNotNull);
      expect(data!.items.length, 2);
      expect(data.items[0].mediaId, 'valid');
      expect(data.items[0].kind, MediaKind.image);
      expect(data.items[1].mediaId, 'also_valid');
    });

  });

  group('parseMediaGallery - 完整有效数据', () {
    test('单图完整字段', () {
      final json = jsonEncode({
        'success': true,
        'message': '已提交 1 张',
        'images': [
          {
            'mediaId': 'e7dd42b0-ee1a-48c9-ac30-d7001480ad97',
            'prompt': '1girl, anime style',
            'modelName': '动漫风17.5',
          },
        ],
        'count': 1,
      });
      final data = parseMediaGallery(json);
      expect(data, isNotNull);
      expect(data!.items.length, 1);
      final item = data.items.first;
      expect(item.mediaId, 'e7dd42b0-ee1a-48c9-ac30-d7001480ad97');
      expect(item.kind, MediaKind.image);
      expect(item.prompt, '1girl, anime style');
    });

    test('多图正常解析（顺序保留）', () {
      final json = jsonEncode({
        'success': true,
        'images': [
          {'mediaId': 'img_1', 'prompt': 'p1'},
          {'mediaId': 'img_2', 'prompt': 'p2'},
          {'mediaId': 'img_3', 'prompt': 'p3'},
        ],
      });
      final data = parseMediaGallery(json);
      expect(data, isNotNull);
      expect(data!.items.map((i) => i.mediaId).toList(),
          ['img_1', 'img_2', 'img_3']);
    });

    test('prompt 缺失时回退为空字符串', () {
      final json = jsonEncode({
        'success': true,
        'images': [
          {'mediaId': 'i1'},
        ],
      });
      final data = parseMediaGallery(json);
      expect(data, isNotNull);
      expect(data!.items.first.prompt, '');
    });
  });
}
