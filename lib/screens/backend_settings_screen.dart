import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../utils/toast_utils.dart';
import '../core/providers/services/network_service_providers.dart';
import '../core/theme/app_typography.dart';

class BackendSettingsScreen extends ConsumerStatefulWidget {
  const BackendSettingsScreen({super.key});

  @override
  ConsumerState<BackendSettingsScreen> createState() =>
      _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends ConsumerState<BackendSettingsScreen> {
  final TextEditingController _hostController = TextEditingController();
  bool _isLoading = true;

  static const String _prefsHostKey = 'backend_host';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(_prefsHostKey) ?? '';
      _hostController.text = host;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    final host = _hostController.text.trim();

    if (host.isEmpty) {
      LoggerService.instance.w(
        '后端HOST为空',
        category: LogCategory.network,
        tags: ['backend', 'validation', 'empty-host'],
      );
      ToastUtils.showWarning('请填写后端 HOST', context: context);
      return;
    }
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      LoggerService.instance.w(
        '后端HOST格式无效: Host: $host',
        category: LogCategory.network,
        tags: ['backend', 'validation', 'invalid-host-format'],
      );
      ToastUtils.showWarning('HOST 应以 http:// 或 https:// 开头', context: context);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceWrapperProvider);
      await apiService.setConfig(host: host);
      if (mounted) {
        ToastUtils.showSuccess('已保存后端配置', context: context);
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '保存后端配置失败',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['backend', 'settings', 'save', 'failed'],
      );
      if (mounted) {
        ToastUtils.showError('保存失败: $e', context: context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    // 移除 _api.dispose() 调用，避免关闭共享的Dio连接
    // _api.dispose(); // 已移除，ApiServiceWrapper是单例，不应由Screen关闭
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '后端服务配置',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'HOST',
                      hintText: '例如: http://127.0.0.1:8000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI 托管模式已使用内置服务器地址并自动完成设备鉴权，'
                    '此项仅本地开发调试自定义后端时有效。',
                    style: AppTypography.bodyProse.copyWith(
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
