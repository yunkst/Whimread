import 'package:flutter/material.dart';

/// 启动链路统一背景色（暗夜书馆炭纸）。
///
/// Android/iOS 原生启动屏背景与此对齐：进程启动 → Flutter 首帧 →
/// 资源校验 → 首页淡入的整条链路里没有一次背景色跳变，
/// 从根源上消除启动期的白屏/闪烁。
const Color kStartupSplashBackground = Color(0xFF241F16);

/// 品牌开屏层。
///
/// 覆盖 Flutter 首帧到资源门卫放行的整段过渡期：主题异步加载、
/// onboarding 状态读取、启动资源校验都发生在这一层之后，用户看到
/// 的是一段连续的品牌动画，而不是白屏与 spinner 交替闪烁。
///
/// 全部使用静态色值（不读 Theme），保证亮/暗主题、主题加载前后
/// 渲染像素完全一致；资源快路径（缓存全命中）下开屏层仅停留
/// 数百毫秒，随首页淡入自然过渡，不额外增加等待。
class AppStartupSplash extends StatefulWidget {
  const AppStartupSplash({super.key});

  @override
  State<AppStartupSplash> createState() => _AppStartupSplashState();
}

class _AppStartupSplashState extends State<AppStartupSplash>
    with SingleTickerProviderStateMixin {
  /// 品牌标记呼吸动画：缓慢往复，传达「加载进行中」而非卡死。
  late final AnimationController _breatheController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _breatheScale = Tween<double>(
    begin: 0.97,
    end: 1.04,
  ).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut));

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kStartupSplashBackground,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(scale: _breatheScale, child: _brandMark),
              const SizedBox(height: 24),
              const Text(
                '随心阅读',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                  color: Color(0xFFE8DCC4),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'WHIMREAD',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 6,
                  color: Color(0xFFB5A482),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 品牌标记：琥珀渐变圆角方块 + 书本图标（渐变与 Agent FAB 同源）。
  Widget get _brandMark => Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB8843A), Color(0xFFD9A05B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33B8843A),
              blurRadius: 48,
              spreadRadius: 8,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_stories,
          size: 46,
          color: Color(0xFF241F16),
        ),
      );
}
