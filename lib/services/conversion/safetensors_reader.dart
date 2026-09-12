/// safetensors 文件读取器
///
/// 格式（https://huggingface.co/docs/safetensors/index#format）：
/// ```
/// [8 字节 LE u64: header 长度 N]
/// [N 字节 UTF-8 JSON header]
/// [数据区]
/// ```
/// JSON header：每个张量名映射到 {dtype, shape, data_offsets: [begin, end]}，
/// data_offsets 相对数据区起始。可选 `__metadata__` 键存放模型元信息。
///
/// 读取策略：只读 header 进内存（几 MB），数据区按张量用 RandomAccessFile
/// 按需读取——12GB 的 checkpoint 也不会整文件载入。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// 纯 Dart 依赖（不 import flutter）：本模块要能在宿主机 `dart run` 下被
// tool/ 脚本复用（真实 checkpoint 的架构识别 / 转换验证），不能引入 dart:ui。
import 'package:meta/meta.dart' show visibleForTesting;

/// safetensors 支持的 dtype
enum StDtype {
  f64,
  f32,
  f16,
  bf16,
  i64,
  i32,
  i16,
  i8,
  u8,
  boolType;

  /// 每元素字节数
  int get byteSize {
    switch (this) {
      case StDtype.f64:
        return 8;
      case StDtype.f32:
        return 4;
      case StDtype.f16:
      case StDtype.bf16:
        return 2;
      case StDtype.i64:
        return 8;
      case StDtype.i32:
        return 4;
      case StDtype.i16:
        return 2;
      case StDtype.i8:
      case StDtype.u8:
      case StDtype.boolType:
        return 1;
    }
  }

  static StDtype parse(String name) {
    switch (name) {
      case 'F64':
        return StDtype.f64;
      case 'F32':
        return StDtype.f32;
      case 'F16':
        return StDtype.f16;
      case 'BF16':
        return StDtype.bf16;
      case 'I64':
        return StDtype.i64;
      case 'I32':
        return StDtype.i32;
      case 'I16':
        return StDtype.i16;
      case 'I8':
        return StDtype.i8;
      case 'U8':
        return StDtype.u8;
      case 'BOOL':
        return StDtype.boolType;
      default:
        throw FormatException('不支持的 safetensors dtype: $name');
    }
  }
}

/// 单个张量的元信息
class StTensorInfo {
  final String name;
  final StDtype dtype;

  /// PyTorch 习惯的 shape（[out, in, ...]，行主序）
  final List<int> shape;

  /// 数据区内的字节偏移 [begin, end)
  final int dataBegin;
  final int dataEnd;

  const StTensorInfo({
    required this.name,
    required this.dtype,
    required this.shape,
    required this.dataBegin,
    required this.dataEnd,
  });

  int get numElements => shape.fold(1, (a, b) => a * b);

  /// 字节数（形状×dtype 一致性由读取时校验）
  int get byteLength => dataEnd - dataBegin;
}

/// safetensors 文件解析结果
class SafetensorsFile {
  final File file;

  /// 数据区在文件中的起始偏移（= 8 + header 长度）
  final int dataStart;

  /// 全部张量（header 顺序）
  final List<StTensorInfo> tensors;

  /// header 里的 `__metadata__`（可能含模型格式说明）
  final Map<String, String> metadata;

  SafetensorsFile({
    required this.file,
    required this.dataStart,
    required this.tensors,
    required this.metadata,
  });

  /// 按名字查找张量
  @visibleForTesting
  StTensorInfo? find(String name) {
    for (final t in tensors) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// 读取一个张量的原始字节（按 header 中声明的 dataBegin/dataEnd 偏移切片）。
  ///
  /// 12GB checkpoint 单张量最大 ~300MB，不会一次性载入整文件。
  /// 失败或截断 → 抛 [StateError]。
  Future<Uint8List> readTensorBytes(StTensorInfo info) async {
    final raf = await file.open();
    try {
      await raf.setPosition(dataStart + info.dataBegin);
      final bytes = await raf.read(info.byteLength);
      if (bytes.length != info.byteLength) {
        throw StateError(
            '张量 "${info.name}" 数据不完整（期望 ${info.byteLength} 字节，读到 ${bytes.length}）');
      }
      return bytes;
    } finally {
      await raf.close();
    }
  }
}

/// 解析 safetensors 文件（只读 header，不载入数据）。
///
/// 抛 [FormatException] 表示文件头损坏或不是 safetensors。
Future<SafetensorsFile> parseSafetensors(File file) async {
  final raf = await file.open();
  try {
    // 1. 读 8 字节 header 长度（LE u64；实际不会超过 2^31，取低 32 位安全）
    final lenBytes = await raf.read(8);
    if (lenBytes.length < 8) {
      throw const FormatException('文件过短：缺少 safetensors header 长度字段');
    }
    final headerLen = ByteData.sublistView(lenBytes).getUint64(0, Endian.little);
    if (headerLen <= 0 || headerLen > 100 * 1024 * 1024) {
      throw FormatException('safetensors header 长度异常: $headerLen');
    }

    // 2. 读 header JSON
    final headerBytes = await raf.read(headerLen);
    if (headerBytes.length < headerLen) {
      throw const FormatException('文件过短：safetensors header 不完整');
    }
    final headerStr = utf8.decode(headerBytes, allowMalformed: false);
    final headerJson = jsonDecode(headerStr);
    if (headerJson is! Map<String, dynamic>) {
      throw const FormatException('safetensors header 不是 JSON 对象');
    }
    return _buildFromHeader(file, headerJson, 8 + headerLen);
  } finally {
    await raf.close();
  }
}

SafetensorsFile _buildFromHeader(
    File file, Map<String, dynamic> headerJson, int dataStart) {
  final tensors = <StTensorInfo>[];
  final metadata = <String, String>{};

  headerJson.forEach((key, value) {
    if (key == '__metadata__') {
      if (value is Map<String, dynamic>) {
        value.forEach((k, v) => metadata[k] = v.toString());
      }
      return;
    }
    if (value is! Map<String, dynamic>) {
      throw FormatException('张量 "$key" 的 header 条目不是对象');
    }
    final dtype = StDtype.parse(value['dtype'] as String);
    final shapeRaw = value['shape'] as List<dynamic>;
    final shape = shapeRaw.map((e) => (e as num).toInt()).toList();
    final offsets = value['data_offsets'] as List<dynamic>;
    final begin = (offsets[0] as num).toInt();
    final end = (offsets[1] as num).toInt();

    // 形状 × dtype 与字节长度一致性校验（截断/损坏文件早期报错）
    final expected = shape.fold(1, (a, b) => a * b) * dtype.byteSize;
    if (end - begin != expected) {
      throw FormatException(
          '张量 "$key" 字节数不符：header 声明 $expected，区间 ${end - begin}');
    }

    tensors.add(StTensorInfo(
      name: key,
      dtype: dtype,
      shape: shape,
      dataBegin: begin,
      dataEnd: end,
    ));
  });

  if (tensors.isEmpty) {
    throw const FormatException('safetensors header 中没有张量');
  }

  return SafetensorsFile(
    file: file,
    dataStart: dataStart,
    tensors: tensors,
    metadata: metadata,
  );
}
