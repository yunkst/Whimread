/// 启动期一次性副作用的串行编排器(crash 上报 → 静默检查更新)。
///
/// 约束:每个阶段「不适用或抛异常」只允许跳过该阶段自身,不得短路后续
/// 阶段——阶段内部需要提前结束时,直接从自己的回调 return 即可,编排器
/// 只看阶段是否正常完成。
///
/// [canContinue] 在每个阶段执行前判定(通常绑定 `State.mounted`),
/// 返回 false 时放弃全部剩余阶段。
class StartupPromptsRunner {
  /// 创建编排器;两个阶段按 [crashReportStage] → [updateCheckStage] 的顺序
  /// 各执行至多一次。
  const StartupPromptsRunner({
    required this.canContinue,
    required this.crashReportStage,
    required this.updateCheckStage,
  });

  /// 是否继续执行(通常绑定 `State.mounted`)。
  final bool Function() canContinue;

  /// 阶段 1:上次 native crash 上报。
  final Future<void> Function() crashReportStage;

  /// 阶段 2:启动期静默检查更新。
  final Future<void> Function() updateCheckStage;

  /// 依次执行各阶段,任何异常只吞掉不外抛。
  ///
  /// [canContinue] 一旦返回 false 立即终止,不再执行也不再判定后续阶段。
  Future<void> run() async {
    final stages = [crashReportStage, updateCheckStage];
    for (final stage in stages) {
      if (!canContinue()) return;
      try {
        await stage();
      } catch (_) {
        // 阶段独立容错:异常只跳过本阶段,不阻塞启动与后续阶段。
      }
    }
  }
}
