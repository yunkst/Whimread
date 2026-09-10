/// Q8_0 量化（ggml 块格式）+ fp16/bf16 解码
///
/// ggml Q8_0 块格式：每 32 个权重一组
/// ```
/// struct block_q8_0 {
///   ggml_half d;      // scale，fp16 存储
///   int8_t    qs[32]; // 量化值
/// };                  // = 34 字节/块
/// ```
/// 量化数学：d = amax(|x|)/127，qs[i] = round(x[i]/d)。
/// 与 ggml `quantize_row_q8_0` 一致（round-half-away-from-zero）。
library;


import 'dart:typed_data';

const int kQ8_0BlockSize = 32;
const int kQ8_0BlockBytes = 34; // 2 (fp16 scale) + 32 (int8)

/// fp16 (IEEE 754 half) → fp32
double fp16ToFp32(int bits) {
  final sign = (bits >> 15) & 0x1;
  final exponent = (bits >> 10) & 0x1F;
  final mantissa = bits & 0x3FF;

  int resultBits;
  if (exponent == 0) {
    if (mantissa == 0) {
      // ±0
      resultBits = sign << 31;
    } else {
      // 次正规：规格化
      var e = -1;
      var m = mantissa;
      while ((m & 0x400) == 0) {
        m <<= 1;
        e--;
      }
      m &= 0x3FF; // 去掉隐藏位
      resultBits = (sign << 31) | ((127 - 15 + e) << 23) | (m << 13);
    }
  } else if (exponent == 0x1F) {
    // Inf/NaN
    resultBits = (sign << 31) | 0x7F800000 | (mantissa << 13);
  } else {
    resultBits = (sign << 31) | ((exponent - 15 + 127) << 23) | (mantissa << 13);
  }
  return _bitsToDouble(resultBits);
}

double _bitsToDouble(int bits) {
  final bd = ByteData(4)..setUint32(0, bits, Endian.little);
  return bd.getFloat32(0, Endian.little);
}

/// bf16（截断 fp32）→ fp32：低 16 位补零
double bf16ToFp32(int bits) {
  final bd = ByteData(4)..setUint32(0, bits << 16, Endian.little);
  return bd.getFloat32(0, Endian.little);
}

/// 从原始字节解码浮点张量为 fp32 列表
///
/// 支持 F32 / F16 / BF16（safetensors 三种浮点格式）。
Float32List decodeToFloat32(Uint8List raw, String dtype, int count) {
  final out = Float32List(count);
  switch (dtype) {
    case 'F32':
      final bd = ByteData.sublistView(raw);
      for (var i = 0; i < count; i++) {
        out[i] = bd.getFloat32(i * 4, Endian.little);
      }
      return out;
    case 'F16':
      final bd = ByteData.sublistView(raw);
      for (var i = 0; i < count; i++) {
        out[i] = fp16ToFp32(bd.getUint16(i * 2, Endian.little));
      }
      return out;
    case 'BF16':
      final bd = ByteData.sublistView(raw);
      for (var i = 0; i < count; i++) {
        out[i] = bf16ToFp32(bd.getUint16(i * 2, Endian.little));
      }
      return out;
    default:
      throw FormatException('不支持的浮点 dtype: $dtype');
  }
}

/// fp32 → fp16 位模式（IEEE 754 half，round-to-nearest-even）
int fp32ToFp16Bits(double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  final bits = bd.getUint32(0, Endian.little);
  final sign = (bits >> 16) & 0x8000;
  final exponent = (bits >> 23) & 0xFF;
  var mantissa = bits & 0x7FFFFF;

  if (exponent == 0xFF) {
    // Inf/NaN
    return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0);
  }

  var e = exponent - 127 + 15;
  if (e >= 0x1F) {
    return sign | 0x7C00; // 溢出 → Inf
  }
  if (e <= 0) {
    // 次正规/零
    if (e < -10) return sign;
    mantissa |= 0x800000;
    final shift = 14 - e;
    final half = mantissa >> shift;
    final rem = mantissa & ((1 << shift) - 1);
    final roundBit = 1 << (shift - 1);
    var result = half;
    if (rem > roundBit || (rem == roundBit && (half & 1) == 1)) {
      result = half + 1;
    }
    return sign | result;
  }

  // 规格化：round-to-nearest-even
  final half = mantissa >> 13;
  final rem = mantissa & 0x1FFF;
  var m = half;
  if (rem > 0x1000 || (rem == 0x1000 && (half & 1) == 1)) {
    m = half + 1;
    if (m > 0x3FF) {
      m = 0;
      e++;
      if (e >= 0x1F) return sign | 0x7C00;
    }
  }
  return sign | (e << 10) | m;
}

/// 把 fp32 列表量化为 Q8_0 块字节序列
///
/// [count] 必须是 32 的倍数（不满足的张量不量化，由调用方过滤）。
Uint8List quantizeQ8_0(Float32List values, int count) {
  final numBlocks = count ~/ kQ8_0BlockSize;
  final out = Uint8List(numBlocks * kQ8_0BlockBytes);
  final bd = ByteData.sublistView(out);

  for (var b = 0; b < numBlocks; b++) {
    final base = b * kQ8_0BlockSize;

    // amax
    var amax = 0.0;
    for (var i = 0; i < kQ8_0BlockSize; i++) {
      final a = values[base + i].abs();
      if (a > amax) amax = a;
    }
    final d = amax / 127.0;

    // scale 存 fp16
    bd.setUint16(b * kQ8_0BlockBytes, fp32ToFp16Bits(d), Endian.little);

    if (d == 0) {
      // 全零块：qs 全 0（scale 已写 0）
      continue;
    }
    final id = 1.0 / d;
    for (var i = 0; i < kQ8_0BlockSize; i++) {
      final v = values[base + i] * id;
      // round-half-away-from-zero（与 ggml 一致）
      final q = v >= 0 ? v + 0.5 : v - 0.5;
      out[b * kQ8_0BlockBytes + 2 + i] = q.truncate().clamp(-127, 127);
    }
  }
  return out;
}

/// Q8_0 块反量化为 fp32（测试校验用）
Float32List dequantizeQ8_0(Uint8List blocks, int count) {
  final out = Float32List(count);
  final bd = ByteData.sublistView(blocks);
  // qs 是 int8（二进制补码），必须按有符号读
  final qs = Int8List.sublistView(blocks);
  final numBlocks = count ~/ kQ8_0BlockSize;
  for (var b = 0; b < numBlocks; b++) {
    final d = fp16ToFp32(bd.getUint16(b * kQ8_0BlockBytes, Endian.little));
    for (var i = 0; i < kQ8_0BlockSize; i++) {
      out[b * kQ8_0BlockSize + i] = qs[b * kQ8_0BlockBytes + 2 + i] * d;
    }
  }
  return out;
}
