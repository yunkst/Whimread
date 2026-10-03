/// NPU（SoC）探测回归测试
///
/// 历史事故：v3.2.0-preview.10 有用户反馈「提示说未检测到 npu」，而同机型
/// 用 Local Dream 能正常检测（vivo V2454DA / Android 16）。根因是探测读
/// `AndroidDeviceInfo.data['socModel']`——device_info_plus 11.x 的 Android
/// build map 里**根本没有 socModel 键**，该值恒为 null，等于所有机型（含骁龙
/// 8 系）都被判成无 NPU。
///
/// 本测试锁死：SoC 型号只能来自原生通道 `com.example.novel_app/device` 的
/// `socInfo`（读 `Build.SOC_MODEL`，与 Local Dream `getDeviceSoc()` 同源），
/// 且 SoC 判定不依赖 DeviceInfoPlugin 能否取到设备基础信息。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/device_soc_provider.dart';

const MethodChannel _deviceChannel =
    MethodChannel('com.example.novel_app/device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void mockSoc(Future<Object?>? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceChannel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_deviceChannel, null);
  });

  Future<DeviceSocInfo> resolve() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(deviceSocProvider.future);
  }

  group('SoC 来源：原生通道 Build.SOC_MODEL', () {
    test('骁龙 8 系读到 SoC 并映射出 NPU 后缀（历史 bug 的正面防线）', () async {
      mockSoc((_) async => <String, Object?>{'socModel': 'SM8750'});

      final info = await resolve();

      expect(calls.map((c) => c.method), ['socInfo'],
          reason: 'SoC 必须来自原生 socInfo 通道，不能只读 device_info');
      expect(info.socModel, 'SM8750');
      expect(info.npuSuffix, '8gen2');
      expect(info.hasNpu, isTrue);
    });

    test('SM8450 映射 8gen1，未登记的 SM 开头型号回退 min', () async {
      mockSoc((_) async => <String, Object?>{'socModel': 'SM8450'});
      expect((await resolve()).npuSuffix, '8gen1');

      calls.clear();
      mockSoc((_) async => <String, Object?>{'socModel': 'SM9999'});
      final fallback = await resolve();
      expect(fallback.socModel, 'SM9999');
      expect(fallback.npuSuffix, 'min');
    });

    test('联发科等非骁龙 SoC 判定为无 NPU', () async {
      mockSoc((_) async => <String, Object?>{'socModel': 'MT6989'});

      final info = await resolve();

      expect(info.socModel, 'MT6989');
      expect(info.npuSuffix, isNull);
      expect(info.hasNpu, isFalse);
    });
  });

  group('探测不到 SoC 时按无 NPU 处理', () {
    test('原生返回 null（API < 31 或未实现）', () async {
      mockSoc((_) async => null);

      final info = await resolve();

      expect(info.socModel, isNull);
      expect(info.npuSuffix, isNull);
      expect(info.hasNpu, isFalse);
    });

    test('socModel 为空串/空白串视同未探测到', () async {
      mockSoc((_) async => <String, Object?>{'socModel': ''});
      expect((await resolve()).socModel, isNull);

      calls.clear();
      mockSoc((_) async => <String, Object?>{'socModel': '   '});
      final blank = await resolve();
      expect(blank.socModel, isNull);
      expect(blank.npuSuffix, isNull);
    });

    test('通道不存在（MissingPluginException）不抛异常，降级为无 NPU', () async {
      mockSoc((_) async => throw MissingPluginException('no impl'));

      final info = await resolve();

      expect(info.socModel, isNull);
      expect(info.npuSuffix, isNull);
    });
  });

  group('异常态告警阈值（决定日志会不会随反馈上传）', () {
    test('API 31+ 仍无 SoC → 告警（反馈 #8 的机型形态）', () {
      expect(shouldWarnSocProbeEmpty(36, null), isTrue,
          reason: 'Android 16 却没探测到 SoC 属异常，需 warning 上报');
      expect(shouldWarnSocProbeEmpty(31, null), isTrue);
    });

    test('拿到 SoC / 老机型 / 设备信息缺失 → 不告警', () {
      expect(shouldWarnSocProbeEmpty(36, 'SM8750'), isFalse);
      expect(shouldWarnSocProbeEmpty(30, null), isFalse,
          reason: 'API < 31 本就没有 SOC_MODEL，属正常态');
      expect(shouldWarnSocProbeEmpty(0, null), isFalse,
          reason: '设备信息读取失败时 sdkInt=0，不误报');
    });
  });
}
