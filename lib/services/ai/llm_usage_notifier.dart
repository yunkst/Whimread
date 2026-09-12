/// LLM 使用事件源（传输层 → 额度刷新的解耦桥）
///
/// [IoLlmHttpClient] 在每次 LLM 请求到达终态（成功 / 失败 / 流结束）时
/// [notify] 一次；关心「AI 被用过」的模块（当前只有设备额度刷新）在
/// 启动期注册 listener 即可，**任何 AI 调用点都无需记得刷额度**。
///
/// 放在 services 层而非直接 import provider：providers → services 的依赖
/// 方向不能反过来，桥接由 main.dart 持有 ProviderContainer 完成。
library;

class LlmUsageNotifier {
  LlmUsageNotifier._();

  static final LlmUsageNotifier instance = LlmUsageNotifier._();

  final List<void Function()> _listeners = <void Function()>[];

  /// 注册「AI 被使用过」回调。listener 内抛异常会被吞掉并记日志，
  /// 绝不影响 LLM 请求本身的返回。
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 注销单个 listener（按引用相等）。重复注销同一个 listener 是 no-op。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// 传输层在请求终态调用。同步扇出，listener 自行做防抖/合流。
  void notify() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        // 消费方异常不得影响 LLM 调用链路
      }
    }
  }
}
