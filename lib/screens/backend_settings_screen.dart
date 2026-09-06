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
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = true;

  static const String _prefsHostKey = 'backend_host';
  static const String _prefsTokenKey = 'backend_token';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(_prefsHostKey) ?? '';
      final token = prefs.getString(_prefsTokenKey) ?? '';
      _hostController.text = host;
      _tokenController.text = token;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    final host = _hostController.text.trim();
    final token = _tokenController.text.trim();

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
      await apiService.setConfig(host: host, token: token);
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
    _tokenController.dispose();
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'TOKEN',
                      hintText: '选填: 访问令牌',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
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
