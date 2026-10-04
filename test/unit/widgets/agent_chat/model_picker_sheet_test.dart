/// Agent 模型选择抽屉测试
///
/// 回归用户反馈「AI 模型配置点开就是个弹窗，什么也选不了」：文字游戏
/// 入口已改为直开本抽屉（LLM 由服务端托管、Key 不落客户端，客户端唯一
/// 能做的就是选模型）。本测试锁定抽屉本身的三条行为：目录渲染（名称 +
/// 倍率 + 当前选中）、选中落库（写 `managed_model_selection` 契约）、
/// 目录不可达时的空态与重试入口。
///
/// 直接 pump 抽屉本体（不经 [showAgentModelPickerSheet] 的路由包装）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/managed_model_provider.dart';
import 'package:novel_app/services/managed_models/managed_model_service.dart';
import 'package:novel_app/widgets/agent_chat/model_picker_sheet.dart';

/// 假 notifier：预置目录、记录 select 调用（不打网络、不写 SP）
class _FakeManagedModelNotifier extends ManagedModelNotifier {
  _FakeManagedModelNotifier(this.initial) : super() {
    state = initial;
  }

  final ManagedModelState initial;
  final List<String> selected = [];
  int refreshCalls = 0;

  @override
  Future<void> refresh({bool force = false}) async {
    refreshCalls++;
    // 真实实现会拉目录，测试里保持预置态（不引入网络/ SP 依赖）
  }

  @override
  Future<void> select(String modelId) async {
    selected.add(modelId);
    state = state.copyWith(selectedModelId: modelId);
  }
}

ManagedModelCatalog _catalog() => ManagedModelCatalog(
      models: const [
        ManagedModel(
            id: 'glm-4.7', displayName: 'GLM 4.7', shortName: 'GLM',
            consumptionRate: 1, isBaseline: true),
        ManagedModel(
            id: 'deepseek-v3', displayName: 'DeepSeek V3', shortName: 'DS',
            consumptionRate: 0.5, isBaseline: false),
      ],
      baselineModelId: 'glm-4.7',
    );

Future<_FakeManagedModelNotifier> _pumpSheet(
  WidgetTester tester,
  ManagedModelState state,
) async {
  final fake = _FakeManagedModelNotifier(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        managedModelProvider.overrideWith((ref) => fake),
      ],
      child: const MaterialApp(home: Scaffold(body: AgentModelPickerSheet())),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  testWidgets('渲染目录：模型名 + 消耗说明 + 当前选中项打勾', (tester) async {
    final fake = await _pumpSheet(
      tester,
      ManagedModelState(catalog: _catalog(), selectedModelId: 'deepseek-v3'),
    );

    expect(find.text('切换 AI 模型'), findsOneWidget);
    expect(find.text('GLM 4.7'), findsOneWidget, reason: '展示模型名');
    expect(find.text('基准'), findsOneWidget, reason: '基准模型带徽标');
    expect(find.text('基准速度 · 消耗最慢'), findsOneWidget);
    expect(find.text('消耗速度约是GLM 的 0.5 倍'), findsOneWidget,
        reason: '非基准模型展示相对基准的消耗倍数');
    expect(fake.refreshCalls, 1, reason: '打开抽屉强制刷一次目录');

    // 当前选中项是 check_circle 圆圈（未选中为 radio_button_off）
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_off), findsOneWidget);
  });

  testWidgets('点选模型：写入选择并关闭抽屉', (tester) async {
    final fake = await _pumpSheet(
      tester,
      ManagedModelState(catalog: _catalog(), selectedModelId: 'glm-4.7'),
    );

    await tester.tap(find.text('DeepSeek V3'));
    await tester.pumpAndSettle();

    expect(fake.selected, ['deepseek-v3'],
        reason: '选择落到 provider（真实实现写 managed_model_selection）');
    expect(find.text('切换 AI 模型'), findsNothing,
        reason: '选中后抽屉关闭');
  });

  testWidgets('目录不可达：空态 + 重试入口', (tester) async {
    final fake = await _pumpSheet(tester, const ManagedModelState());

    expect(find.text('暂无可用模型'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(fake.refreshCalls, greaterThan(1), reason: '重试按钮再次拉目录');
  });
}
