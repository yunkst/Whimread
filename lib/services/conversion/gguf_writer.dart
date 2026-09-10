/// GGUF v3 容器写出器
///
/// 文件布局（与 ggml `gguf_write_to_file` 一致，alignment=32）：
/// ```
/// magic "GGUF"      4B
/// version u32 = 3   4B
/// tensor_count u64  8B
/// kv_count u64 = 0  8B            ← sd.cpp convert 不写任何 KV
/// tensor info ×N:
///   name: u64 len + bytes
///   n_dims: u32
///   ne: u64 × n_dims              ← ggml 序（ne[0] 最内维 = PyTorch shape 末维）
///   type: u32（ggml type 枚举）
///   offset: u64                   ← 相对数据段起始，32 对齐
/// padding 到 32 对齐
/// tensor data ×N（按 offset）
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// ggml type 枚举值（GGUF tensor type 字段用）
const int kGgmlTypeF32 = 0;
const int kGgmlTypeF16 = 1;
const int kGgmlTypeQ8_0 = 8;
const int kGgmlTypeBF16 = 30;

const int kGgufAlignment = 32;

/// GGUF 文件头 magic：ASCII "GGUF"（G=0x47 G=0x47 U=0x55 F=0x46）
///
/// 导入校验（[ImageModelImportService]）与引擎侧校验（LocalSdCppBackend）
/// 共用此常量，保证两处规则不漂移。
const List<int> kGgufMagic = [0x47, 0x47, 0x55, 0x46];

/// 要写出的一个张量
class GgufTensorEntry {
  final String name;

  /// ggml ne 序维度（调用方负责从 PyTorch shape 逆序）
  final List<int> ne;

  /// ggml type 枚举值（kGgmlTypeF32 / F16 / Q8_0 / BF16）
  final int ggmlType;

  /// 张量数据字节（写入时按序落盘）
  final Future<List<int>> Function() dataLoader;

  GgufTensorEntry({
    required this.name,
    required this.ne,
    required this.ggmlType,
    required this.dataLoader,
  });

  /// 该张量在文件中的字节数
  int get byteCount {
    final numElements = ne.fold(1, (a, b) => a * b);
    switch (ggmlType) {
      case kGgmlTypeF32:
        return numElements * 4;
      case kGgmlTypeF16:
      case kGgmlTypeBF16:
        return numElements * 2;
      case kGgmlTypeQ8_0:
        final numBlocks = numElements ~/ 32;
        if (numElements % 32 != 0) {
          throw FormatException('张量 "$name" 元素数 $numElements 不是 32 的倍数，不能 Q8_0');
        }
        return numBlocks * 34;
      default:
        throw FormatException('未支持的 ggml type: $ggmlType');
    }
  }
}

/// 计算元数据段长度（header + tensor infos + 对齐 padding）
int metadataLength(List<GgufTensorEntry> tensors) {
  var len = 4 + 4 + 8 + 8; // magic + version + tensor_count + kv_count
  for (final t in tensors) {
    len += 8 + utf8.encode(t.name).length; // name
    len += 4; // n_dims
    len += 8 * t.ne.length; // ne
    len += 4; // type
    len += 8; // offset
  }
  final aligned = (len + kGgufAlignment - 1) ~/ kGgufAlignment * kGgufAlignment;
  return aligned;
}

/// 写出 GGUF 文件。
///
/// 张量数据通过 [GgufTensorEntry.dataLoader] 惰性加载（保持流式：任一时刻
/// 只有一个张量的数据在内存）。
Future<void> writeGgufFile(String path, List<GgufTensorEntry> tensors) async {
  // 1. 计算各张量 offset（32 对齐）
  final metaLen = metadataLength(tensors);
  final offsets = List<int>.filled(tensors.length, 0);
  var cursor = 0;
  for (var i = 0; i < tensors.length; i++) {
    offsets[i] = cursor;
    cursor += tensors[i].byteCount;
    cursor = (cursor + kGgufAlignment - 1) ~/ kGgufAlignment * kGgufAlignment;
  }

  // 2. 总文件大小（元数据 + 数据段）
  final totalSize = metaLen + cursor;

  // 3. 构造元数据段
  final metaBuf = BytesBuilder(copy: false);
  final header = ByteData(24);
  header.setUint8(0, 0x47); // 'G'
  header.setUint8(1, 0x47); // 'G'
  header.setUint8(2, 0x55); // 'U'
  header.setUint8(3, 0x46); // 'F'
  header.setUint32(4, 3, Endian.little); // version
  header.setUint64(8, tensors.length, Endian.little); // tensor_count
  header.setUint64(16, 0, Endian.little); // kv_count = 0
  metaBuf.add(header.buffer.asUint8List());

  for (var i = 0; i < tensors.length; i++) {
    final t = tensors[i];
    final nameB = utf8.encode(t.name);
    final nb = ByteData(8);
    nb.setUint64(0, nameB.length, Endian.little);
    metaBuf.add(nb.buffer.asUint8List());
    metaBuf.add(nameB);

    final info = ByteData(4 + 8 * t.ne.length + 4 + 8);
    info.setUint32(0, t.ne.length, Endian.little);
    for (var d = 0; d < t.ne.length; d++) {
      info.setUint64(4 + 8 * d, t.ne[d], Endian.little);
    }
    info.setUint32(4 + 8 * t.ne.length, t.ggmlType, Endian.little);
    info.setUint64(8 + 8 * t.ne.length, offsets[i], Endian.little);
    metaBuf.add(info.buffer.asUint8List());
  }

  // padding 到 metaLen
  if (metaBuf.length < metaLen) {
    metaBuf.add(Uint8List(metaLen - metaBuf.length));
  }

  // 4. 落盘：truncate 预分配 → 写元数据 → 逐张量 seek 写数据（流式）
  final sink = File(path).openSync(mode: FileMode.write);
  try {
    sink.truncateSync(totalSize);
    sink.setPositionSync(0);
    sink.writeFromSync(metaBuf.toBytes());

    for (var i = 0; i < tensors.length; i++) {
      final data = await tensors[i].dataLoader();
      if (data.length != tensors[i].byteCount) {
        throw StateError(
            '张量 "${tensors[i].name}" 数据长度不符：期望 ${tensors[i].byteCount}，实际 ${data.length}');
      }
      sink.setPositionSync(metaLen + offsets[i]);
      sink.writeFromSync(data);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
}
