/// safetensors 读取器单元测试
///
/// 用合成 fixture（8字节长度 + JSON header + 裸数据）验证解析、dtype、
/// 形状校验、损坏检测。fp16/bf16 解码数学在 quantize_q8_0_test 里覆盖。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/conversion/safetensors_reader.dart';
import '../../../helpers/safetensors_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('st_reader_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('parseSafetensors', () {
    test('解析 F32 张量：dtype/shape/数据读回', () async {
      // 2x3 F32 = 24 字节
      final data = Uint8List(24);
      final bd = ByteData.sublistView(data);
      for (var i = 0; i < 6; i++) {
        bd.setFloat32(i * 4, i + 0.5, Endian.little);
      }
      final f = writeSyntheticSafetensors({'weight': ('F32', [2, 3], data)},
          dir: tmp, name: 'f32');
      final st = await parseSafetensors(f);

      expect(st.tensors, hasLength(1));
      final t = st.tensors.first;
      expect(t.name, 'weight');
      expect(t.dtype, StDtype.f32);
      expect(t.shape, [2, 3]);
      expect(t.byteLength, 24);

      final raw = await st.readTensorBytes(t);
      final back = ByteData.sublistView(raw);
      expect(back.getFloat32(16, Endian.little), 4.5);
    });

    test('F16 / BF16 dtype 识别', () async {
      final f = writeSyntheticSafetensors({
        'a': ('F16', [4], Uint8List(8)),
        'b': ('BF16', [4], Uint8List(8)),
      }, dir: tmp, name: 'dtypes');
      final st = await parseSafetensors(f);
      expect(st.find('a')!.dtype, StDtype.f16);
      expect(st.find('b')!.dtype, StDtype.bf16);
    });

    test('__metadata__ 解析（不进张量列表）', () async {
      final f = writeSyntheticSafetensors({
        'w': ('F32', [2], Uint8List(8)),
      },
          metadata: {'modelspec.predict_key': 'epsilon'},
          dir: tmp, name: 'meta');
      final st = await parseSafetensors(f);
      expect(st.metadata['modelspec.predict_key'], 'epsilon');
      expect(st.tensors, hasLength(1));
    });

    test('多张量偏移连续正确', () async {
      final a = Uint8List(8)..fillRange(0, 8, 0xAA);
      final b = Uint8List(16)..fillRange(0, 16, 0xBB);
      final f = writeSyntheticSafetensors({
        'first': ('F16', [4], a),
        'second': ('F32', [4], b),
      }, dir: tmp, name: 'multi');
      final st = await parseSafetensors(f);

      expect(st.find('first')!.dataBegin, 0);
      expect(st.find('first')!.dataEnd, 8);
      expect(st.find('second')!.dataBegin, 8);
      expect(st.find('second')!.dataEnd, 24);

      final rawB = await st.readTensorBytes(st.find('second')!);
      expect(rawB.every((b) => b == 0xBB), isTrue);
    });

    test('文件过短 → FormatException', () async {
      final f = File('${tmp.path}/short.safetensors')
        ..writeAsBytesSync([1, 2, 3]);
      expect(() => parseSafetensors(f), throwsA(isA<FormatException>()));
    });

    test('header 长度异常 → FormatException', () async {
      final buf = BytesBuilder();
      final lenBytes = ByteData(8)..setUint64(0, 1 << 40, Endian.little);
      buf.add(lenBytes.buffer.asUint8List());
      buf.add(Uint8List(16));
      final f = File('${tmp.path}/badlen.safetensors')
        ..writeAsBytesSync(buf.toBytes());
      expect(() => parseSafetensors(f), throwsA(isA<FormatException>()));
    });

    test('形状×dtype 与字节长度不符 → FormatException', () async {
      // 声明 2x3 F32（24字节）但只给 16 字节
      final header =
          '{"w":{"dtype":"F32","shape":[2,3],"data_offsets":[0,16]}}';
      final buf = BytesBuilder();
      final lenBytes = ByteData(8)
        ..setUint64(0, header.length, Endian.little);
      buf.add(lenBytes.buffer.asUint8List());
      buf.add(header.codeUnits);
      buf.add(Uint8List(16));
      final f = File('${tmp.path}/mismatch.safetensors')
        ..writeAsBytesSync(buf.toBytes());
      expect(() => parseSafetensors(f), throwsA(isA<FormatException>()));
    });

    test('空张量列表 → FormatException', () async {
      final header = '{}';
      final buf = BytesBuilder();
      final lenBytes = ByteData(8)
        ..setUint64(0, header.length, Endian.little);
      buf.add(lenBytes.buffer.asUint8List());
      buf.add(header.codeUnits);
      final f = File('${tmp.path}/empty.safetensors')
        ..writeAsBytesSync(buf.toBytes());
      expect(() => parseSafetensors(f), throwsA(isA<FormatException>()));
    });
  });
}
