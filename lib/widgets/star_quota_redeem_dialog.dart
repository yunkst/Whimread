/// GitHub Star 兑换免费额度对话框。
///
/// 与 [StarPromptDialog]（纯引导点赞）不同，本对话框是「兑换」动作入口：
/// 1. 文案说明：Star 项目可补一次免费额度
/// 2. 用户输入 GitHub 用户名
/// 3. 主按钮「提交验证」→ [DeviceAuthService.redeemStarQuota]
///    成功 → pop(result)，调用方展示新余额
///    失败 → 错误留在对话框内（不 pop），用户可改后重试
///
/// 错误提示使用 DeviceAuthException.message（与服务端 error_code 一一映射，
/// 见 `device_auth_service.mapRedeemDioError`），本组件不做二次翻译。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/device/device_auth_service.dart';
import '../services/logger_service.dart';
import '../services/native_crash_reporter.dart' show kGitHubRepo;

/// GitHub 用户名规则：字母/数字/连字符，不以连字符开头/结尾，1-39 位。
/// 与后端 `github_stars.is_valid_github_login` 保持同一判定，提交前先本地挡一道。
final RegExp _githubLoginPattern = RegExp(
  r'^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$',
);

class StarQuotaRedeemDialog extends StatefulWidget {
  /// 兑换服务注入点（默认单例；测试可注入 fake）。
  final DeviceAuthService? service;

  const StarQuotaRedeemDialog({super.key, this.service});

  @override
  State<StarQuotaRedeemDialog> createState() => _StarQuotaRedeemDialogState();
}

class _StarQuotaRedeemDialogState extends State<StarQuotaRedeemDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _errorText;

  DeviceAuthService get _service => widget.service ?? DeviceAuthService.instance;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openGitHub() async {
    try {
      await launchUrl(Uri.parse(kGitHubRepo),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      // 无浏览器等场景静默失败，与设置页「去 GitHub 点 Star」入口一致
      LoggerService.instance.w('打开 GitHub 失败: $e',
          category: LogCategory.ai, tags: ['star-redeem']);
    }
  }

  Future<void> _submit() async {
    final login = _controller.text.trim();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final result = await _service.redeemStarQuota(login);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on DeviceAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '兑换失败，请稍后再试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      icon: Icon(Icons.star_outline, color: cs.primary, size: 40),
      title: const Text('点 Star 补充免费额度'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '「随心阅读」的 AI 托管额度由独立开发者自费承担。'
              '去 GitHub 给项目点一个 ⭐ Star，即可免费补充一次额度：',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              enabled: !_submitting,
              autofillHints: const [],
              decoration: const InputDecoration(
                labelText: 'GitHub 用户名',
                hintText: '例如 octocat',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return '请输入 GitHub 用户名';
                if (!_githubLoginPattern.hasMatch(value)) {
                  return '格式不正确：仅字母/数字/连字符，1-39 位';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // 「去点 Star」与「提交验证」并排等宽展示：先点 Star 再回来验证，
        // 两个动作视觉等重，弱化主次顺序避免「去点 Star」被当成次要按钮忽略。
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : _openGitHub,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('去点 Star'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_outlined, size: 16),
                label: Text(_submitting ? '验证中…' : '提交验证'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
