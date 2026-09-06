/// PreferencesService 偏好设置服务单元测试
///
/// 验证 SharedPreferences 的各种读写操作：
/// - String / Int / Double / Bool 读写
/// - StringList 读写
/// - containsKey / remove / clear / getKeys
/// - setMultiple / getMultiple 批量操作
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/preferences_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/services/preferences_service.dart';

void main() {
  // 初始化 SharedPreferences mock
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PreferencesService', () {
    late PreferencesService prefs;

    setUp(() async {
      // 使用 SharedPreferences mock
      await SharedPreferences.getInstance();
      prefs = PreferencesService.instance;
    });

    group('String 读写', () {
      test('setString 和 getString 应正常工作', () async {
        await prefs.setString('key1', 'value1');
        expect(await prefs.getString('key1'), 'value1');
      });

      test('getString 不存在的 key 应返回默认值', () async {
        expect(await prefs.getString('nonexistent'), '');
        expect(await prefs.getString('nonexistent', defaultValue: 'fallback'),
            'fallback');
      });
    });

    group('Int 读写', () {
      test('setInt 和 getInt 应正常工作', () async {
        await prefs.setInt('count', 42);
        expect(await prefs.getInt('count'), 42);
      });

      test('getInt 不存在的 key 应返回默认值', () async {
        expect(await prefs.getInt('nonexistent'), 0);
        expect(await prefs.getInt('nonexistent', defaultValue: 100), 100);
      });
    });

    group('Double 读写', () {
      test('setDouble 和 getDouble 应正常工作', () async {
        await prefs.setDouble('price', 3.14);
        expect(await prefs.getDouble('price'), 3.14);
      });

      test('getDouble 不存在的 key 应返回默认值', () async {
        expect(await prefs.getDouble('nonexistent'), 0.0);
      });
    });

    group('Bool 读写', () {
      test('setBool 和 getBool 应正常工作', () async {
        await prefs.setBool('enabled', true);
        expect(await prefs.getBool('enabled'), isTrue);

        await prefs.setBool('enabled', false);
        expect(await prefs.getBool('enabled'), isFalse);
      });

      test('getBool 不存在的 key 应返回默认值', () async {
        expect(await prefs.getBool('nonexistent'), isFalse);
        expect(await prefs.getBool('nonexistent', defaultValue: true), isTrue);
      });
    });

    group('StringList 读写', () {
      test('setStringList 和 getStringList 应正常工作', () async {
        await prefs.setStringList('tags', ['小说', '玄幻', '完结']);
        expect(await prefs.getStringList('tags'), ['小说', '玄幻', '完结']);
      });

      test('getStringList 不存在的 key 应返回空列表', () async {
        expect(await prefs.getStringList('nonexistent'), isEmpty);
      });
    });

    group('containsKey / remove / clear / getKeys', () {
      test('containsKey 应正确判断 key 是否存在', () async {
        await prefs.setString('exists', 'value');
        expect(await prefs.containsKey('exists'), isTrue);
        expect(await prefs.containsKey('notexists'), isFalse);
      });

      test('remove 应删除指定 key', () async {
        await prefs.setString('to_remove', 'value');
        expect(await prefs.containsKey('to_remove'), isTrue);

        await prefs.remove('to_remove');
        expect(await prefs.containsKey('to_remove'), isFalse);
      });

      test('clear 应清空所有数据', () async {
        await prefs.setString('key1', 'value1');
        await prefs.setInt('key2', 42);

        await prefs.clear();

        expect(await prefs.containsKey('key1'), isFalse);
        expect(await prefs.containsKey('key2'), isFalse);
      });

      test('getKeys 应返回所有 key 集合', () async {
        await prefs.setString('a', '1');
        await prefs.setString('b', '2');

        final keys = await prefs.getKeys();
        expect(keys, containsAll(['a', 'b']));
      });
    });

    group('setMultiple / getMultiple', () {
      test('setMultiple 应支持混合类型', () async {
        await prefs.setMultiple({
          'str': 'value',
          'int': 42,
          'bool': true,
          'list': ['a', 'b'],
        });

        expect(await prefs.getString('str'), 'value');
        expect(await prefs.getInt('int'), 42);
        expect(await prefs.getBool('bool'), isTrue);
        expect(await prefs.getStringList('list'), ['a', 'b']);
      });

      test('getMultiple 应只返回请求的 key', () async {
        await prefs.setString('a', '1');
        await prefs.setString('b', '2');
        await prefs.setString('c', '3');

        final result = await prefs.getMultiple({'a', 'c'});

        expect(result.keys, containsAll(['a', 'c']));
        expect(result.containsKey('b'), isFalse);
        expect(result['a'], '1');
        expect(result['c'], '3');
      });
    });
  });
}
