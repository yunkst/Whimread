/// Q8_0 量化数学单元测试
///
/// 验证 fp16/bf16 解码、量化 scale/qs 数学、round-trip 误差上界。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/conversion/quantize_q8_0.dart';

void main() {
  group('fp16 解码', () {
    test('特殊值', () {
      expect(fp16ToFp32(0x0000), 0.0);
      expect(fp16ToFp32(0x8000), -0.0);
      expect(fp16ToFp32(0x3C00), 1.0); // 1.0
      expect(fp16ToFp32(0xBC00), -1.0);
      expect(fp16ToFp32(0x4000), 2.0);
      expect(fp16ToFp32(0x7C00).isInfinite, isTrue); // +Inf
      expect(fp16ToFp32(0xFC00).isInfinite, isTrue); // -Inf
      expect(fp16ToFp32(0x7E00).isNaN, isTrue); // NaN
    });

    test('常规值精度（±2^-11 相对误差内）', () {
      for (final v in [0.5, 1.25, -3.75, 100.0, 0.001]) {
        final bits = fp32ToFp16Bits(v);
        final back = fp16ToFp32(bits);
        final relErr = ((back - v).abs() / v.abs());
        expect(relErr, lessThan(0.001), reason: 'v=$v back=$back');
      }
    });

    test('round-trip fp32→fp16→fp32 次正规', () {
      // 极小值 → 次正规/零，不应崩溃
      final bits = fp32ToFp16Bits(1e-8);
      expect(fp16ToFp32(bits), inInclusiveRange(0, 1e-6));
    });
  });

  group('bf16 解码', () {
    test('1.0 / -2.0', () {
      // 1.0f = 0x3F800000 → bf16 = 0x3F80
      expect(bf16ToFp32(0x3F80), 1.0);
      // -2.0f = 0xC0000000 → bf16 = 0xC000
      expect(bf16ToFp32(0xC000), -2.0);
    });
  });

  group('quantizeQ8_0', () {
    test('恒定块：scale=值/127，qs 全 127', () {
      final values = Float32List(32)..fillRange(0, 32, 2.54);
      final q = quantizeQ8_0(values, 32);

      expect(q.length, kQ8_0BlockBytes);
      final d = fp16ToFp32(
          ByteData.sublistView(q).getUint16(0, Endian.little));
      expect(d, closeTo(2.54 / 127, 1e-4));
      // 全部 qs = 127（round(2.54/(2.54/127)) = 127）
      for (var i = 0; i < 32; i++) {
        expect(q[2 + i], 127);
      }
    });

    test('全零块：scale=0，qs 全 0', () {
      final values = Float32List(64); // 两块全零
      final q = quantizeQ8_0(values, 64);
      for (var i = 0; i < q.length; i++) {
        expect(q[i], 0, reason: 'offset $i');
      }
    });

    test('负值：qs 符号正确（int8 补码）', () {
      final values = Float32List(32);
      for (var i = 0; i < 32; i++) {
        values[i] = -127.0 + i; // -127..-96
      }
      final q = quantizeQ8_0(values, 32);
      // amax=127 → d=1 → qs[i] = round(value[i])；qs 按 int8 读
      final signed = Int8List.sublistView(q);
      for (var i = 0; i < 32; i++) {
        expect(signed[2 + i], -127 + i);
      }
    });

    test('round-trip 绝对误差上界：|err| ≤ d/2 ≤ 1/254', () {
      var seed = 42;
      int nextRand() {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return seed;
      }

      const count = 32 * 100;
      final values = Float32List(count);
      for (var i = 0; i < count; i++) {
        values[i] = (nextRand() % 20000 - 10000) / 10000.0; // [-1, 1]
      }
      final q = quantizeQ8_0(values, count);
      final back = dequantizeQ8_0(q, count);

      // 理论上界：块内误差 ≤ d/2，d = amax/127 ≤ 1/127 → ≤ 0.00394
      var maxAbsErr = 0.0;
      for (var i = 0; i < count; i++) {
        final err = (back[i] - values[i]).abs();
        if (err > maxAbsErr) maxAbsErr = err;
      }
      expect(maxAbsErr, lessThan(0.005));
    });

    test('非 32 倍数 count 的调用约定（由调用方保证）', () {
      final values = Float32List(33); // 33 不是 32 倍数
      // 只量化前 32 个（调用方负责过滤）
      final q = quantizeQ8_0(values, 32);
      expect(q.length, kQ8_0BlockBytes);
    });
  });

  group('fp32ToFp16Bits', () {
    test('常量位模式', () {
      expect(fp32ToFp16Bits(1.0), 0x3C00);
      expect(fp32ToFp16Bits(0.0), 0x0000);
      expect(fp32ToFp16Bits(-1.0), 0xBC00);
    });
  });
}
