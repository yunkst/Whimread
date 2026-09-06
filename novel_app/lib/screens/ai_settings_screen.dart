import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../utils/toast_utils.dart';

/// AI 设定页面
///
/// AI 托管模式后，LLM 供应商配置已由内置后端承担，本页仅保留：
/// **AI 设定**（作家设定 prompt）。
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aiWriterPromptController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _aiWriterPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _aiWriterPromptController.text =
        prefs.getString('ai_writer_prompt') ?? '';
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'ai_writer_prompt', _aiWriterPromptController.text.trim());
      if (mounted) {
        ToastUtils.showSuccess('设置已保存');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI 配置',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // ── LLM 配置管理 ──
                  Text(
                    'LLM 配置',
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 16,
                      color: context.appColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '管理多个 LLM 后端配置（API URL、Key、模型），在 Agent 和章节生成中切换使用。',
                    style: AppTypography.bodyProse.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: context.appColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // AI 托管模式：LLM 由内置后端提供，无需用户配置供应商
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: const Text('AI 服务已内置'),
                      subtitle: const Text('开箱即用，无需配置 AI 供应商'),
                      trailing: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── AI 设定 ──
                  Text(
                    'AI 设定',
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 16,
                      color: context.appColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _aiWriterPromptController,
                    decoration: const InputDecoration(
                      labelText: 'AI 作家设定',
                      hintText: '例如：你是一个专业的网络小说作家...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
    );
  }
}
