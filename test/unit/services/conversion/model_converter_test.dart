/// 架构识别 + 转换编排端到端测试
///
/// 张量名 fixture 来自真实 SD1.5/SDXL checkpoint 的命名模式
/// （已用 D:\Comfyui 真实模型通过 tool/inspect_safetensors.dart 验证）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/conversion/arch_detector.dart';
import 'package:novel_app/services/conversion/gguf_writer.dart';
import 'package:novel_app/services/conversion/model_converter.dart';
import 'package:novel_app/services/conversion/quantize_q8_0.dart';
import 'package:novel_app/services/conversion/safetensors_reader.dart';
import '../../../helpers/safetensors_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('arch_conv_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('detectArch', () {
    test('SD1.5：cond_stage_model + first_stage_model', () {
      final names = [
        'model.diffusion_model.input_blocks.0.0.weight',
        'model.diffusion_model.out.2.weight',
        'cond_stage_model.transformer.text_model.encoder.layers.0.self_attn.q_proj.weight',
        'first_stage_model.encoder.conv_in.weight',
        'first_stage_model.decoder.conv_out.weight',
      ];
      final d = detectArch(names);
      expect(d.arch, SdArch.sd15);
      expect(d.isSupported, isTrue);
      expect(d.arch.defaultSize, 512);
    });

    test('SDXL：conditioner.embedders.0/1 双编码器', () {
      final names = [
        'model.diffusion_model.input_blocks.0.0.weight',
        'conditioner.embedders.0.transformer.text_model.encoder.layers.0.self_attn.q_proj.weight',
        'conditioner.embedders.1.model.transformer.resblocks.0.attn.in_proj_weight',
        'first_stage_model.encoder.conv_in.weight',
      ];
      final d = detectArch(names);
      expect(d.arch, SdArch.sdxl);
      expect(d.arch.defaultSize, 1024);
    });

    test('Flux（double_blocks）→ 不支持', () {
      final names = [
        'double_blocks.0.img_attn.qkv.weight',
        'single_blocks.0.linear1.weight',
      ];
      expect(detectArch(names).arch, SdArch.unsupported);
    });

    test('仅 VAE（无 UNet/TE）→ 不支持', () {
      final names = [
        'decoder.up_blocks.0.resnets.0.conv1.weight',
        'encoder.down_blocks.0.conv.weight',
      ];
      expect(detectArch(names).arch, SdArch.unsupported);
    });

    test('空列表 → 不支持', () {
      expect(detectArch(const []).arch, SdArch.unsupported);
    });
  });

  group('端到端转换（微型 SD1.5 结构）', () {
    test('safetensors → gguf → 结构/数值校验', () async {
      // ---- 构造微型 SD1.5 checkpoint ----
      // 量化规则（ne[0] = PyTorch shape 末维）：
      //   - 2D 线性权重 [out, in] 且 in%32==0 → 量化
      //   - 4D conv 权重 ne[0]=kh*kw 末维 → 不满足 %32 → 保持 F32（真实行为）
      //   - .bias / time_embed.* / 含 embedding → 名称排除
      final tensors = <String, (String, List<int>, Uint8List)>{
        // conv 3x3：ne[0]=3 → 不量化
        'model.diffusion_model.input_blocks.0.0.weight':
            ('F32', [8, 4, 3, 3], seqF32(8 * 4 * 3 * 3)),
        'model.diffusion_model.input_blocks.0.0.bias':
            ('F32', [8], seqF32(8)),
        // time_embed：名称排除
        'model.diffusion_model.time_embed.0.weight':
            ('F32', [32, 32], seqF32(32 * 32)),
        // 注意力线性层：ne[0]=64 ✓ 量化
        'model.diffusion_model.input_blocks.1.1.transformer_blocks.0.attn1.to_q.weight':
            ('F32', [32, 64], seqF32(32 * 64)),
        // TE 线性层：ne[0]=32 ✓ 量化
        'cond_stage_model.transformer.text_model.encoder.layers.0.mlp.fc1.weight':
            ('F32', [8, 32], seqF32(8 * 32)),
        // VAE conv 1x1：ne[0]=1 → 不量化
        'first_stage_model.encoder.conv_in.weight':
            ('F32', [8, 4, 1, 1], seqF32(8 * 4)),
      };
      final srcFile = writeSyntheticSafetensors(tensors, dir: tmp, name: 'sd15_tiny');

      // ---- plan + convert ----
      final plan = await planConversion(srcFile);
      expect(plan.detection.arch, SdArch.sd15);

      final outPath = '${tmp.path}/out.gguf';
      final result = await convertToGguf(plan, outPath);

      expect(File(outPath).existsSync(), isTrue);
      expect(result.arch, SdArch.sd15);
      expect(result.quantizedCount, 2, reason: 'to_q + fc1 两个线性层');
      expect(result.keptCount, 4);

      // ---- 回读校验 ----
      final bytes = await File(outPath).readAsBytes();
      final bd = ByteData.sublistView(bytes);

      // magic / version / counts
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'GGUF');
      expect(bd.getUint32(4, Endian.little), 3);
      expect(bd.getUint64(8, Endian.little), 6); // tensor_count
      expect(bd.getUint64(16, Endian.little), 0); // kv_count

      // 解析 tensor infos
      var pos = 24;
      final infos = <String, (List<int>, int, int)>{}; // name → (ne, type, offset)
      for (var n = 0; n < 6; n++) {
        final nameLen = bd.getUint64(pos, Endian.little);
        pos += 8;
        final name = String.fromCharCodes(bytes.sublist(pos, pos + nameLen));
        pos += nameLen;
        final nDims = bd.getUint32(pos, Endian.little);
        pos += 4;
        final ne = <int>[];
        for (var d = 0; d < nDims; d++) {
          ne.add(bd.getUint64(pos, Endian.little));
          pos += 8;
        }
        final type = bd.getUint32(pos, Endian.little);
        pos += 4;
        final offset = bd.getUint64(pos, Endian.little);
        pos += 8;
        infos[name] = (ne, type, offset);
      }

      // 名称透传（原始 CompVis 命名）
      expect(infos.keys,
          contains('model.diffusion_model.input_blocks.1.1.transformer_blocks.0.attn1.to_q.weight'));

      // 维度 = PyTorch shape 逆序（ggml ne 序）
      final q = infos['model.diffusion_model.input_blocks.1.1.transformer_blocks.0.attn1.to_q.weight']!;
      expect(q.$1, [64, 32]);
      expect(q.$2, kGgmlTypeQ8_0);

      // conv 3x3 保持 F32、维度逆序 [3,3,4,8]
      final conv = infos['model.diffusion_model.input_blocks.0.0.weight']!;
      expect(conv.$1, [3, 3, 4, 8]);
      expect(conv.$2, kGgmlTypeF32);

      // bias 保持 F32
      final b = infos['model.diffusion_model.input_blocks.0.0.bias']!;
      expect(b.$2, kGgmlTypeF32);
      expect(b.$1, [8]);

      // 数据段校验：bias 原样（F32 直拷）
      // bias 数据 = F32 [-3.5, -2.5, ...]，在文件数据区搜索 -1.5f（0x0000C0BF）
      // 与 -0.5f（0x000000BF）字节模式确认原样拷贝
      final pattern = Uint8List.fromList([0x00, 0x00, 0xC0, 0xBF]);
      var found = false;
      for (var i = 200; i < bytes.length - 4; i++) {
        if (bytes[i] == pattern[0] &&
            bytes[i + 1] == pattern[1] &&
            bytes[i + 2] == pattern[2] &&
            bytes[i + 3] == pattern[3]) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'bias 的 F32 数据应原样存在');
    });

    test('量化数值 round-trip：单张量 Q8_0 误差上界', () {
      final src = Float32List(8 * 4 * 3 * 3);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i % 17) - 8 + 0.25;
      }
      final q = quantizeQ8_0(src, src.length);
      final back = dequantizeQ8_0(q, src.length);
      for (var i = 0; i < src.length; i++) {
        if (src[i].abs() > 0.5) {
          final rel = ((back[i] - src[i]).abs() / src[i].abs());
          expect(rel, lessThan(0.05),
              reason: 'i=$i src=${src[i]} back=${back[i]}');
        }
      }
    });

    test('不支持的架构 → ConversionException', () async {
      final f = writeSyntheticSafetensors({
        'double_blocks.0.img_attn.qkv.weight': ('F32', [32, 32], seqF32(1024)),
      }, dir: tmp, name: 'flux_like');
      expect(() => planConversion(f), throwsA(isA<ConversionException>()));
    });

    test('v-pred 元数据 → ArchDetection 标志', () async {
      final f = writeSyntheticSafetensors({
        'model.diffusion_model.input_blocks.0.0.weight':
            ('F32', [8, 4, 1, 1], seqF32(32)),
        'cond_stage_model.transformer.text_model.encoder.layers.0.mlp.fc1.weight':
            ('F32', [8, 8], seqF32(64)),
        'first_stage_model.encoder.conv_in.weight':
            ('F32', [8, 4, 1, 1], seqF32(32)),
      },
          dir: tmp,
          name: 'vprd',
          metadata: {'modelspec.predict_key': 'v'});
      final plan = await planConversion(f);
      expect(plan.detection.isVPrediction, isTrue);
    });
  });
}
