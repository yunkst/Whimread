/// ManagedModelCatalog / ManagedModelService 单元测试
///
/// 覆盖:
///   - ManagedModelCatalog.parse:字段缺失/边界值/排序/baseline 校正
///   - rateLabel:不暴露绝对价格,统一以 baseline 短称为参考点
///   - ManagedModelService 选择持久化(getSelectedModelId / setSelectedModelId)
///   - resolveForRequest:选中不存在 → 落回 baseline / 目录未知 → 信任本地选择
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/services/managed_models/managed_model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ManagedModelCatalog.parse', () {
    test('完整字段 → 正确解析 + baseline 校正', () {
      final json = {
        'object': 'list',
        'baseline_model_id': 'deepseek-v4-flash',
        'data': [
          {
            'id': 'deepseek-v4-flash',
            'display_name': 'DeepSeek V4 Flash',
            'short_name': 'Flash',
            'consumption_rate': 1,
            'is_baseline': true,
            'description': '标准档',
          },
          {
            'id': 'deepseek-v4-pro',
            'display_name': 'DeepSeek V4 Pro',
            'short_name': 'Pro',
            'consumption_rate': 5,
            'is_baseline': false,
            'description': '增强档',
          },
        ],
      };
      final c = ManagedModelCatalog.parse(json);
      expect(c.baselineModelId, 'deepseek-v4-flash');
      expect(c.models.length, 2);
      expect(c.byId('deepseek-v4-pro')?.consumptionRate, 5);
      expect(c.byId('deepseek-v4-flash')?.isBaseline, true);
      expect(c.byId('deepseek-v4-pro')?.isBaseline, false);
    });

    test('缺少 baseline_model_id → 用 is_baseline=true 兜底', () {
      final c = ManagedModelCatalog.parse({
        'data': [
          {
            'id': 'a',
            'display_name': 'A',
            'consumption_rate': 2,
            'is_baseline': false,
          },
          {
            'id': 'b',
            'display_name': 'B',
            'consumption_rate': 1,
            'is_baseline': true,
          },
        ],
      });
      expect(c.baselineModelId, 'b');
    });

    test('consumption_rate 是整数 → 转 double', () {
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'a',
        'data': [
          {
            'id': 'a',
            'display_name': 'A',
            'consumption_rate': 1,
          },
          {
            'id': 'b',
            'display_name': 'B',
            'consumption_rate': 5, // int
          },
        ],
      });
      expect(c.byId('b')?.consumptionRate, 5.0);
    });

    test('consumption_rate 是小数 → 保留', () {
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'a',
        'data': [
          {
            'id': 'a',
            'display_name': 'A',
            'consumption_rate': 1,
          },
          {
            'id': 'b',
            'display_name': 'B',
            'consumption_rate': 2.5,
          },
        ],
      });
      expect(c.byId('b')?.consumptionRate, 2.5);
    });

    test('条目缺 id / 空 id / rate<=0 → 跳过', () {
      final c = ManagedModelCatalog.parse({
        'data': [
          {'id': '', 'consumption_rate': 1},
          {'id': '   ', 'consumption_rate': 2},
          {'consumption_rate': 1}, // 无 id
          {'id': 'good', 'consumption_rate': 3},
        ],
      });
      expect(c.models.length, 1);
      expect(c.models.first.id, 'good');
      expect(c.baselineModelId, 'good'); // 唯一有效条目自动 baseline
    });

    test('display_name / short_name / description 缺失 → 回退规则', () {
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'x',
        'data': [
          {
            'id': 'x',
            // 无 display_name / short_name / description
            'consumption_rate': 1,
          },
        ],
      });
      final m = c.models.first;
      expect(m.displayName, 'x'); // fallback id
      expect(m.shortName, isNull);
      expect(m.description, isNull);
    });

    test('display_name 全空白 → fallback id', () {
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'x',
        'data': [
          {
            'id': 'x',
            'display_name': '   ',
            'consumption_rate': 1,
          },
        ],
      });
      expect(c.models.first.displayName, 'x');
    });

    test('空 data → 抛 FormatException', () {
      expect(
        () => ManagedModelCatalog.parse({'data': []}),
        throwsFormatException,
      );
    });

    test('非 Map 响应 → 抛 FormatException', () {
      expect(() => ManagedModelCatalog.parse(null), throwsFormatException);
      expect(() => ManagedModelCatalog.parse([]), throwsFormatException);
    });

    test('缺 data 字段 → 抛 FormatException', () {
      expect(
        () => ManagedModelCatalog.parse({'baseline_model_id': 'a'}),
        throwsFormatException,
      );
    });

    test('misconfig: 两个 model 都标 is_baseline=true → 校正后只剩 baselineId 一条',
        () {
      // 后端误标: flash 与 pro 都 is_baseline=true,但 baseline_model_id 指 flash
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'flash',
        'data': [
          {
            'id': 'flash',
            'display_name': 'Flash',
            'consumption_rate': 1,
            'is_baseline': true,
          },
          {
            'id': 'pro',
            'display_name': 'Pro',
            'consumption_rate': 5,
            'is_baseline': true, // 误标
          },
        ],
      });
      expect(c.byId('flash')?.isBaseline, true);
      expect(c.byId('pro')?.isBaseline, false); // 校正降级
      expect(c.baselineModelId, 'flash');
    });

    test('misconfig: baseline_model_id 与任何 is_baseline=true 的 id 不一致 → 校正到 baselineModelId',
        () {
      // 后端误标: baseline_model_id='flash',但只有 pro 标 is_baseline=true
      final c = ManagedModelCatalog.parse({
        'baseline_model_id': 'flash',
        'data': [
          {
            'id': 'flash',
            'display_name': 'Flash',
            'consumption_rate': 1,
            'is_baseline': false, // 误标
          },
          {
            'id': 'pro',
            'display_name': 'Pro',
            'consumption_rate': 5,
            'is_baseline': true, // 误标
          },
        ],
      });
      expect(c.byId('flash')?.isBaseline, true); // 校正优先 baseline_model_id
      expect(c.byId('pro')?.isBaseline, false);
      expect(c.baselineModelId, 'flash');
    });
  });

  group('ManagedModelCatalog.rateLabel(展示规则)', () {
    ManagedModelCatalog makeCatalog({
      required String baselineId,
      required List<Map<String, dynamic>> models,
    }) {
      final list = [
        for (final m in models)
          ManagedModel(
            id: m['id'] as String,
            displayName: m['display_name'] as String? ?? m['id'] as String,
            shortName: m['short_name'] as String?,
            consumptionRate: (m['rate'] as num).toDouble(),
            isBaseline: m['id'] == baselineId,
            description: null,
          ),
      ];
      return ManagedModelCatalog(models: list, baselineModelId: baselineId);
    }

    test('baseline 模型 → 「基准速度 · 消耗最慢」', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'display_name': 'Flash', 'short_name': 'Flash', 'rate': 1},
          {'id': 'pro', 'display_name': 'Pro', 'short_name': 'Pro', 'rate': 5},
        ],
      );
      final flash = c.byId('flash')!;
      expect(c.rateLabel(flash), '基准速度 · 消耗最慢');
    });

    test('整数倍率(5) → 「消耗速度约是 Flash 的 5 倍」', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'short_name': 'Flash', 'rate': 1},
          {'id': 'pro', 'short_name': 'Pro', 'rate': 5},
        ],
      );
      expect(c.rateLabel(c.byId('pro')!), '消耗速度约是Flash 的 5 倍');
    });

    test('小数倍率(2.5) → 「消耗速度约是 Flash 的 2.5 倍」', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'short_name': 'Flash', 'rate': 1},
          {'id': 'mid', 'short_name': 'Mid', 'rate': 2.5},
        ],
      );
      expect(c.rateLabel(c.byId('mid')!), '消耗速度约是Flash 的 2.5 倍');
    });

    test('baseline 没有 short_name → 用 display_name 作参考', () {
      final c = makeCatalog(
        baselineId: 'deepseek-v4-flash',
        models: [
          {'id': 'deepseek-v4-flash', 'display_name': 'DeepSeek V4 Flash', 'rate': 1},
          {'id': 'pro', 'short_name': 'Pro', 'rate': 8},
        ],
      );
      expect(
        c.rateLabel(c.byId('pro')!),
        '消耗速度约是DeepSeek V4 Flash 的 8 倍',
      );
    });

    test('不暴露绝对价格 — 文案不出现 token / 点 / 单价 等字眼', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'short_name': 'Flash', 'rate': 1},
          {'id': 'pro', 'short_name': 'Pro', 'rate': 5},
        ],
      );
      final label = c.rateLabel(c.byId('pro')!);
      // 防止后续误改引入绝对价格文案
      expect(label, isNot(contains('token')));
      expect(label, isNot(contains('Token')));
      expect(label, isNot(contains('点/')));
      expect(label, isNot(contains('元')));
      expect(label, isNot(contains('￥')));
    });
  });

  group('ManagedModel.shortLabel', () {
    test('有 short_name → 用 short_name', () {
      const m = ManagedModel(
        id: 'x',
        displayName: 'Long Display Name',
        shortName: 'Short',
        consumptionRate: 1,
        isBaseline: true,
      );
      expect(m.shortLabel, 'Short');
    });

    test('无 short_name → 用 displayName', () {
      const m = ManagedModel(
        id: 'x',
        displayName: 'Long Display Name',
        shortName: null,
        consumptionRate: 1,
        isBaseline: true,
      );
      expect(m.shortLabel, 'Long Display Name');
    });

    test('short_name 是空字符串 → 用 displayName', () {
      const m = ManagedModel(
        id: 'x',
        displayName: 'Long Display Name',
        shortName: '',
        consumptionRate: 1,
        isBaseline: true,
      );
      expect(m.shortLabel, 'Long Display Name');
    });
  });

  group('ManagedModelService 持久化', () {
    late ManagedModelService svc;

    setUp(() {
      svc = ManagedModelService.instance;
    });

    test('初始未选 → getSelectedModelId 返回 null', () async {
      expect(await svc.getSelectedModelId(), isNull);
    });

    test('setSelectedModelId → getSelectedModelId 读回', () async {
      await svc.setSelectedModelId('deepseek-v4-pro');
      expect(await svc.getSelectedModelId(), 'deepseek-v4-pro');
    });

    test('setSelectedModelId(null) → 清空(回到 null)', () async {
      await svc.setSelectedModelId('x');
      expect(await svc.getSelectedModelId(), 'x');
      await svc.setSelectedModelId(null);
      expect(await svc.getSelectedModelId(), isNull);
    });

    test('setSelectedModelId("") → 视作清空', () async {
      await svc.setSelectedModelId('x');
      await svc.setSelectedModelId('');
      expect(await svc.getSelectedModelId(), isNull);
    });
  });

  group('ManagedModelService.resolveForRequest', () {
    ManagedModelCatalog makeCatalog({
      required String baselineId,
      required List<Map<String, dynamic>> models,
    }) {
      final list = [
        for (final m in models)
          ManagedModel(
            id: m['id'] as String,
            displayName: m['id'] as String,
            shortName: m['id'] as String,
            consumptionRate: (m['rate'] as num).toDouble(),
            isBaseline: m['id'] == baselineId,
            description: null,
          ),
      ];
      return ManagedModelCatalog(models: list, baselineModelId: baselineId);
    }

    test('目录已知 + 选中在目录内 → 返回选中', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'rate': 1},
          {'id': 'pro', 'rate': 5},
        ],
      );
      final svc = ManagedModelService.instance;
      expect(svc.resolveForRequest(catalog: c, selectedId: 'pro'), 'pro');
    });

    test('目录已知 + 选中不在目录 → 落回 baseline', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'rate': 1},
          {'id': 'pro', 'rate': 5},
        ],
      );
      final svc = ManagedModelService.instance;
      // 用户选了已被服务端下架的模型 → 自动降级
      expect(
        svc.resolveForRequest(catalog: c, selectedId: 'archived-model'),
        'flash',
      );
    });

    test('目录已知 + 未选 → 返回 baseline', () {
      final c = makeCatalog(
        baselineId: 'flash',
        models: [
          {'id': 'flash', 'rate': 1},
          {'id': 'pro', 'rate': 5},
        ],
      );
      final svc = ManagedModelService.instance;
      expect(svc.resolveForRequest(catalog: c, selectedId: null), 'flash');
    });

    test('目录未知 + 有选中 → 信任本地选择(网络恢复前的本地兜底)', () {
      final svc = ManagedModelService.instance;
      expect(
        svc.resolveForRequest(catalog: null, selectedId: 'pro'),
        'pro',
      );
    });

    test('目录未知 + 未选 → 返回 null(让后端走 baseline)', () {
      final svc = ManagedModelService.instance;
      expect(svc.resolveForRequest(catalog: null, selectedId: null), isNull);
    });
  });
}