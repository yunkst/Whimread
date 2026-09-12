import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/onboarding_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 新手引导首次启动向导
///
/// 全屏分步向导，引导新用户认识核心能力并完成 AI 配置：
/// 1. 欢迎页（APP 定位）
/// 2. 🌟 配置 AI 引擎（关键步骤：填一个 LLM 地址 + Key 即可解锁大部分 AI 能力）
/// 3. 找书方式介绍（浏览器浏览 → 添加小说）
/// 4. 阅读增强亮点（AI 特写 / 插图 / 改写），含一行进阶功能提示
/// 5. 完成
///
/// 触发时机：首次安装后未标记 `onboarding_completed` 时，由 main.dart 路由到此页面。
/// 完成或跳过后调用 [OnboardingNotifier.completeOnboarding]，状态变更会触发
/// main.dart 重建到 HomePage。
class OnboardingScreen extends ConsumerStatefulWidget {
  /// 是否为「重新查看引导」模式
  ///
  /// true：仅展示，完成/跳过仅关闭页面，不修改引导完成标记。
  /// false（默认）：完成或跳过后调用 completeOnboarding，触发 _AppRoot 切回 HomePage。
  final bool isReviewMode;

  const OnboardingScreen({super.key, this.isReviewMode = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// 向导步骤总数
  static const int _stepCount = 5;

  final PageController _pageController = PageController();

  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 跳过引导（标记完成，不再显示）
  Future<void> _skipOnboarding() async {
    if (widget.isReviewMode) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(onboardingNotifierProvider.notifier).completeOnboarding();
  }

  /// 前进到下一页
  void _goToNextPage() {
    if (_currentPage < _stepCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 完成引导，进入主界面
  Future<void> _finishOnboarding() async {
    if (widget.isReviewMode) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(onboardingNotifierProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏：跳过按钮
            _buildTopBar(context),
            // 内容区
            Expanded(
              child: PageView(
                controller: _pageController,
                // 配置类页面允许滑动，但配置项意外清空风险低；
                // 关键的 AI 步骤保留滑动以允许回看，靠"下一步"前进。
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  // 0 - 欢迎
                  _buildInfoPage(
                    icon: Icons.auto_stories,
                    iconColor: colorScheme.primary,
                    title: '欢迎使用「随心阅读」',
                    description: '聚合多个小说站点资源，离线缓存随时阅读，'
                        '更有 AI 阅读增强让阅读体验更沉浸。',
                  ),
                  // 1 - AI 已内置（AI 托管模式：无需用户配置）
                  _buildInfoPage(
                    icon: Icons.auto_awesome,
                    iconColor: context.appColors.agentAccent,
                    title: 'AI 已内置就绪',
                    description: '无需配置任何 AI 供应商，安装即可使用'
                        ' AI 阅读增强：特写、改写、角色提取、创作助手。',
                  ),
                  // 2 - 找书
                  _buildInfoPage(
                    icon: Icons.travel_explore,
                    iconColor: colorScheme.tertiary,
                    title: '轻松找到你想看的书',
                    description: '在「浏览器」中打开小说网站，浏览到目录页后，'
                        '点右下角「添加小说」按钮即可一键收入书架。',
                    bullets: const [
                      '浏览器内访问任意小说站点',
                      '目录页自动识别，一键加入书架',
                      '加入后离线缓存章节，随时畅读',
                    ],
                  ),
                  // 3 - 阅读增强亮点（底部含进阶功能入口提示）
                  _buildHighlightPageWithHint(context),
                  // 4 - 完成
                  _buildInfoPage(
                    icon: Icons.rocket_launch,
                    iconColor: colorScheme.primary,
                    title: '一切就绪',
                    description: 'AI 能力已内置，开箱即用。'
                        '如需自部署后端，可在「设置」中调整，'
                        '或重新查看本引导。',
                  ),
                ],
              ),
            ),
            // 底部：进度指示 + 主操作按钮
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  /// 构建顶部跳过栏
  Widget _buildTopBar(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: TextButton(
          onPressed: _skipOnboarding,
          child: const Text('跳过'),
        ),
      ),
    );
  }

  /// 构建信息展示页（图标 + 标题 + 描述 + 要点列表）
  Widget _buildInfoPage({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    List<String> bullets = const [],
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 大图标
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 60, color: iconColor),
            ),
          ),
          const SizedBox(height: 32),
          // 标题
          Center(
            child: Text(
              title,
              style: AppTypography.onboardingTitle.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          // 描述
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          // 要点列表
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...bullets.map((b) => _buildBullet(b, iconColor)),
          ],
        ],
      ),
    );
  }

  /// 构建「阅读增强亮点」整页：顶部信息页 + 底部 _AdvancedHintBanner
  ///
  /// 把 hint 作为页内元素（不是独立的 PageView child），保持
  /// `PageView.children.length == _stepCount`（5 == 5）。
  /// `_buildInfoPage` 已自带 horizontal: 32 padding，hint 自带 32 padding，
  /// 所以这里只需 Column 垂直堆叠 + SizedBox 间距。
  Widget _buildHighlightPageWithHint(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildInfoPage(
            icon: Icons.auto_awesome,
            iconColor: context.appColors.agentAccent,
            title: 'AI 让阅读更有趣',
            description: '配置好 AI 引擎后，阅读时即可调用这些能力，'
                '为文字补充画面感，或改写不满意的段落。',
            bullets: const [
              'AI 特写：为情节生成沉浸式扩写',
              '场景插图：用文字生成配图',
              '段落改写：一键优化文笔',
              '角色对话：和书中角色直接聊天',
            ],
          ),
        ),
        const SizedBox(height: 32),
        const _AdvancedHintBanner(),
      ],
    );
  }

  /// 构建要点条目
  Widget _buildBullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部进度指示 + 主按钮
  Widget _buildBottomBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _stepCount - 1;

    // 主按钮文案与行为
    final primaryLabel =
        isLastPage ? (widget.isReviewMode ? '完成' : '开始使用') : '下一步';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          // 进度指示器
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_stepCount, (index) {
              final isActive = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          // 主操作按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                if (isLastPage) {
                  _finishOnboarding();
                } else {
                  _goToNextPage();
                }
              },
              child: Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「阅读增强亮点」页底部的轻提示：一行引导新手知道还有更多能力
///
/// 居中、次级色、不喧宾夺主。
class _AdvancedHintBanner extends StatelessWidget {
  const _AdvancedHintBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32, left: 32, right: 32),
      child: Text(
        '还有 Agent 记忆、生图模型管理等进阶能力，'
        '可在「设置 → AI」中按需配置。',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
