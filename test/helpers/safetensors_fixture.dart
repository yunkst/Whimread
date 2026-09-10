/// 生图转换链路测试共享 fixture
///
/// - [seqF32]：确定性 F32 字节序列（[0..n) 循环值 -4.5..3.5），断言可复算
/// - [writeSyntheticSafetensors]：最小合法 safetensors 写出器
///   （8字节 header 长度 + 紧凑 JSON + 裸数据），自动计算 data_offsets
library;

import 'dart:io';
import 'dart:typed_data';

/// 确定性 F32 字节序列：i → (i % 9) - 4 + 0.5
Uint8List seqF32(int count) {
  final bytes = Uint8List(count * 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < count; i++) {
    bd.setFloat32(i * 4, (i % 9) - 4 + 0.5, Endian.little);
  }
  return bytes;
}

/// 最小合法 safetensors 写出器。
///
/// [tensors]: name → (dtype, shape, rawBytes)。offsets 自动按声明顺序排列。
/// [metadata] 写入 `__metadata__`。
/// 文件落在 [dir]（调用方负责清理；通常传测试 setUp 建的 tmp 目录），
/// 名字 = [name].safetensors。
File writeSyntheticSafetensors(
  Map<String, (String, List<int>, Uint8List)> tensors, {
  Map<String, String>? metadata,
  required Directory dir,
  String name = 'model',
}) {
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final entries = <String>[];
  var offset = 0;
  for (final e in tensors.entries) {
    final (dtype, shape, bytes) = e.value;
    entries.add(
        '"${e.key}":{"dtype":"$dtype","shape":[${shape.join(",")}],"data_offsets":[$offset,${offset + bytes.length}]}');
    offset += bytes.length;
  }
  if (metadata != null) {
    final m = metadata.entries.map((e) => '"${e.key}":"${e.value}"').join(',');
    entries.add('"__metadata__":{$m}');
  }
  final header = '{${entries.join(",")}}';
  final headerBytes = header.codeUnits;

  final buf = BytesBuilder();
  final lenBytes = ByteData(8)..setUint64(0, headerBytes.length, Endian.little);
  buf.add(lenBytes.buffer.asUint8List());
  buf.add(headerBytes);
  for (final e in tensors.entries) {
    buf.add(e.value.$3);
  }

  return File('${dir.path}/$name.safetensors')
    ..writeAsBytesSync(buf.toBytes());
}
