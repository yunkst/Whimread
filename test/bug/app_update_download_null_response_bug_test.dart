import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/app_update_service.dart';

void main() {
  group('AppUpdateService - 版本号比较（下载前检查）', () {
    // 验证修复后 hasNewVersion 不会因为响应/字段为 null 而崩溃
    // 历史上下载链路曾因 ApiServiceWrapper 改动导致 null 响应未处理
    final service = AppUpdateService();

    test('主版本号更大应判定为有新版本', () {
      expect(service.hasNewVersion('1.0.0', '2.0.0'), isTrue);
    });

    test('次版本号更大应判定为有新版本', () {
      expect(service.hasNewVersion('1.0.0', '1.1.0'), isTrue);
    });

    test('修订版本号更大应判定为有新版本', () {
      expect(service.hasNewVersion('1.0.0', '1.0.1'), isTrue);
    });

    test('相同版本号应判定为无新版本', () {
      expect(service.hasNewVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('当前版本较新应判定为无新版本', () {
      expect(service.hasNewVersion('2.0.0', '1.0.0'), isFalse);
    });

    test('版本号位数不足应自动补齐（1.0 == 1.0.0）', () {
      expect(service.hasNewVersion('1.0', '1.0.0'), isFalse);
      expect(service.hasNewVersion('1.0', '1.0.1'), isTrue);
    });

    test('非法版本号字符串应返回 false 不抛异常（防御 null/异常响应）', () {
      // 修复前：如果 latest 为空或格式异常会抛出
      // 修复后：应安全返回 false
      expect(service.hasNewVersion('1.0.0', ''), isFalse);
      expect(service.hasNewVersion('1.0.0', 'invalid'), isFalse);
      expect(service.hasNewVersion('', '1.0.0'), isFalse);
    });
  });
}
