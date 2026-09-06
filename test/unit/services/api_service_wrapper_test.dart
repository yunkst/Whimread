import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/api_service_wrapper.dart';

/// ApiServiceWrapper 构造与初始化单元测试
///
/// 验证当前设计：单 Dio 注入构造 + 只读 dio/isInitialized 暴露 + 非单例。
///（早期版本曾支持 Dio + DefaultApi 双注入，已随 OpenAPI DefaultApi 弃用而移除。）
void main() {
  group('ApiServiceWrapper - Dio 注入', () {
    test('可通过构造函数注入 Dio 实例', () {
      final dio = Dio(BaseOptions());
      final api = ApiServiceWrapper(dio);

      expect(api.dio, same(dio));
    });

    test('不传参时创建默认 Dio 实例', () {
      final api = ApiServiceWrapper();

      expect(api.dio, isA<Dio>());
    });

    test('isInitialized 初始为 false', () {
      final api = ApiServiceWrapper();

      expect(api.isInitialized, isFalse);
    });
  });

  group('ApiServiceWrapper - 非单例', () {
    test('每个实例相互独立', () {
      final a = ApiServiceWrapper();
      final b = ApiServiceWrapper();

      expect(identical(a, b), isFalse);
    });

    test('可创建多个独立实例', () {
      final services = List.generate(5, (_) => ApiServiceWrapper());

      for (var i = 0; i < services.length; i++) {
        for (var j = i + 1; j < services.length; j++) {
          expect(identical(services[i], services[j]), isFalse);
        }
      }
    });
  });
}
