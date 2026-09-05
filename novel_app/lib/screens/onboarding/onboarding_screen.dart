import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/onboarding_providers.dart';
import '../../core/providers/service_providers.dart';
import '../../core/providers/ui_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/llm_config.dart';
import '../../services/logger_service.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/onboarding/ai_capabilities_section.dart';

/// 新手引导首次启动向导
///
/// 全屏分步向导，引导新用户认识核心能力并完成 AI 配置：
/// 1. 欢迎页（APP 定位）
/// 2. 🌟 配置 AI 引擎（关键步骤：填一个 LLM 地址 + Key 即可解锁大部分 AI 能力）
/// 3. 找书方式介绍（浏览器浏览 → 添加小说）
/// 4. 阅读增强亮点（AI 特写 / 插图 / 改写），含一行进阶功能提示
/// 5. 完成
///
/// 「进阶功能」入口在后续设置页 → 「进阶服务」→ 「后端服务配置」（本引导不再单设一步）。
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

  /// 各步骤索引（与 PageView 顺序一致）
  static const int _indexAi = 1;

  final PageController _pageController = PageController();
  final TextEditingController _aiApiUrlController =
      TextEditingController(text: 'https://api.deepseek.com');
  final TextEditingController _aiApiKeyController = TextEditingController();
  final TextEditingController _aiModelController =
      TextEditingController(text: 'deepseek-v4-pro');

  int _currentPage = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _aiApiUrlController.dispose();
    _aiApiKeyController.dispose();
    _aiModelController.dispose();
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

  /// 跳转到设置页对应 Tab
  void _goToSettings() {
    if (widget.isReviewMode) {
      // review 模式：先关闭向导弹层，再切 Tab
      Navigator.of(context).maybePop();
    }
    ref
        .read(homeTabIndexNotifierProvider.notifier)
        .switchTo(HomeTabIndex.settings);
  }

  /// 保存 AI 引擎配置并前进
  ///
  /// 这是向导的关键步骤。用户填入一个 OpenAI 兼容的 LLM 地址 + Key，
  /// 即可解锁 DSL Engine 驱动的全部 AI 能力（特写、改写、摘要、角色提取等）。
  /// 留空可稍后配置。
  Future<void> _saveAiAndContinue() async {
    final apiUrl = _aiApiUrlController.text.trim();
    final apiKey = _aiApiKeyController.text.trim();

    // 任一为空视为"稍后配置"，直接前进
    if (apiUrl.isEmpty || apiKey.isEmpty) {
      _goToNextPage();
      return;
    }

    if (Uri.tryParse(apiUrl)?.isAbsolute != true) {
      ToastUtils.showWarning('请输入有效的 API 地址', context: context);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final model = _aiModelController.text.trim();

      // 保存到 llm_configs 表（新的多配置序列）
      // 同时保留旧 key 写入，保证向后兼容
      final configService = ref.read(llmConfigServiceProvider);
      final now = DateTime.now();
      final id = await configService.saveConfig(LlmConfig(
        name: '默认配置',
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        isDefault: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ));
      await configService.setDefault(id);

      // 兼容旧 key（引导页写 dsl_engine_* 以兼容未迁移的旧逻辑）
      final prefs = ref.read(preferencesServiceProvider);
      await prefs.setString('dsl_engine_api_url', apiUrl);
      await prefs.setString('dsl_engine_api_key', apiKey);
      if (model.isNotEmpty) {
        await prefs.setString('dsl_engine_model', model);
      }
      await prefs.setBool('dsl_engine_enabled', true);

      LoggerService.instance.i(
        '新手引导：已保存 LLM 配置（AI 引擎）',
        category: LogCategory.ai,
        tags: ['onboarding', 'ai', 'config'],
      );
      if (mounted) {
        ToastUtils.showSuccess('AI 引擎配置已保存，AI 功能已解锁',
            context: context);
        _goToNextPage();
      }
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '新手引导：保存 AI 引擎配置失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ai,
        tags: ['onboarding', 'ai', 'config', 'error'],
      );
      if (mounted) {
        ToastUtils.showError('保存失败: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
                  // 1 - AI 引擎（关键）
                  _buildAiConfigPage(context),
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
                    description: '后续可在「设置」中随时调整后端地址、'
                        'AI 引擎，或重新查看本引导。',
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

  /// 构建 AI 引擎配置页（关键步骤）
  Widget _buildAiConfigPage(BuildContext context) {
    final theme = Theme.of(context);
    final aiColor = context.appColors.agentAccent;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图标 + 标题
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: aiColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 50, color: aiColor),
            ),
          ),
          const SizedBox(height: 16),
          // 「关键」标签
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: aiColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '核心步骤 · 解锁 AI',
                style: TextStyle(
                  fontSize: 12,
                  color: aiColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '配置 AI 引擎',
              style: AppTypography.onboardingTitle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '填入一个 OpenAI 兼容的 LLM 地址和密钥（如 DeepSeek、OpenAI、'
            '本地 Ollama 等），即可解锁大部分 AI 能力。填写后立即生效。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // 配置输入
          TextField(
            controller: _aiApiUrlController,
            decoration: const InputDecoration(
              labelText: 'LLM API 地址',
              hintText: 'https://api.deepseek.com',
              prefixIcon: Icon(Icons.api),
              border: OutlineInputBorder(),
              helperText: 'OpenAI 兼容接口地址',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aiApiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-xxx',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
              helperText: '在 LLM 服务商后台获取',
            ),
            autocorrect: false,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aiModelController,
            decoration: const InputDecoration(
              labelText: '模型名（可留空）',
              hintText: 'deepseek-chat / gpt-4o-mini / qwen-turbo ...',
              prefixIcon: Icon(Icons.memory),
              border: OutlineInputBorder(),
              helperText: '不填则使用 LLM 服务商默认模型',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 20),
          // 解锁能力说明
          const AiCapabilitiesSection(),
        ],
      ),
    );
  }

  /// 构建底部进度指示 + 主按钮
  Widget _buildBottomBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _stepCount - 1;
    final isAiPage = _currentPage == _indexAi;

    // 主按钮文案与行为
    String primaryLabel;
    if (isLastPage) {
      primaryLabel = widget.isReviewMode ? '完成' : '开始使用';
    } else if (isAiPage) {
      primaryLabel = '保存并继续';
    } else {
      primaryLabel = '下一步';
    }

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
              onPressed: _isSaving
                  ? null
                  : () {
                      if (isLastPage) {
                        _finishOnboarding();
                      } else if (isAiPage) {
                        _saveAiAndContinue();
                      } else {
                        _goToNextPage();
                      }
                    },
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(primaryLabel),
            ),
          ),
          // AI 配置页提供"稍后配置 / 去设置页详细配置"
          if (isAiPage) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : _goToNextPage,
                  child: const Text('稍后配置'),
                ),
                Text(
                  '·',
                  style: TextStyle(color: colorScheme.outline),
                ),
                TextButton(
                  onPressed: _isSaving ? null : _goToSettings,
                  child: const Text('去设置页详细配置'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 「阅读增强亮点」页底部的轻提示：一行引导新手知道还有进阶功能入口
///
/// 居中、次级色、不喧宾夺主；路径「设置 → 进阶服务 → 后端服务配置」
/// 与 Task 2 设置页的分组标题、Tile 标题字字对应。
class _AdvancedHintBanner extends StatelessWidget {
  const _AdvancedHintBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32, left: 32, right: 32),
      child: Text(
        '还有 AI 出图、数据备份等进阶功能，'
        '可在「设置 → 进阶服务」中按需开启。',
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
