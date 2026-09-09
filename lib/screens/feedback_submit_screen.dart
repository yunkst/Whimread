/// 问题反馈提交页面
///
/// 用户填写标题 / 描述 / 复现步骤 / 联系方式,可选附带近期日志,
/// 通过 [FeedbackService] 提交到 feedback 云函数。
/// 提交成功 toast + pop;失败 inline 红字,表单内容保留。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/feedback_service.dart';
import '../services/logger_service.dart';
import '../utils/toast_utils.dart';

class FeedbackSubmitScreen extends ConsumerStatefulWidget {
  const FeedbackSubmitScreen({super.key, this.service});

  /// 反馈服务,默认 [FeedbackService.instance];测试可注入 fake。
  final FeedbackService? service;

  @override
  ConsumerState<FeedbackSubmitScreen> createState() =>
      _FeedbackSubmitScreenState();
}

class _FeedbackSubmitScreenState extends ConsumerState<FeedbackSubmitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();
  final _contactController = TextEditingController();

  FeedbackCategory _category = FeedbackCategory.bug;
  bool _includeLogs = false;
  bool _submitting = false;
  String? _errorText;

  /// 当前可附带的日志快照(开关打开时才采集展示,提交时以采集结果为准)
  List<LogEntry> _logPreview = const [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _toggleIncludeLogs(bool value) {
    setState(() {
      _includeLogs = value;
      _logPreview =
          value ? FeedbackService.collectRecentLogs() : const <LogEntry>[];
    });
  }

  int get _warnCount => _logPreview
      .where((e) => e.level.index >= LogLevel.warning.index)
      .length;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final logs =
          _includeLogs ? FeedbackService.collectRecentLogs() : const <LogEntry>[];
      await (widget.service ?? FeedbackService.instance).submit(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        steps: _stepsController.text.trim().isEmpty
            ? null
            : _stepsController.text.trim(),
        contact: _contactController.text.trim().isEmpty
            ? null
            : _contactController.text.trim(),
        includeLogs: logs.isNotEmpty,
        kind: FeedbackKind.userReport,
      );
      if (!mounted) return;
      ToastUtils.showSuccess('已收到，谢谢！');
      Navigator.of(context).pop();
    } on FeedbackSubmitException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '提交失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '问题反馈',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text(
              '此反馈将匿名发送到后端，用于产品改进。',
              style: AppTypography.metaItalic.copyWith(
                color: appColors.inkSoft,
              ),
            ),
            const SizedBox(height: 16),

            // 类别
            SegmentedButton<FeedbackCategory>(
              segments: FeedbackCategory.values
                  .map((c) => ButtonSegment(value: c, label: Text(c.label)))
                  .toList(),
              selected: {_category},
              onSelectionChanged: (selection) =>
                  setState(() => _category = selection.first),
            ),
            const SizedBox(height: 16),

            // 标题
            TextFormField(
              controller: _titleController,
              maxLength: 100,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '一句话概括问题',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '标题不能为空';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 问题描述
            TextFormField(
              controller: _descriptionController,
              maxLength: 5000,
              enabled: !_submitting,
              minLines: 4,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '问题描述',
                hintText: '发生了什么？期望的行为是什么？',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '描述不能为空';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 复现步骤
            TextFormField(
              controller: _stepsController,
              maxLength: 5000,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '复现步骤（可选）',
                hintText: '例如：打开某小说 → 派 agent 读三章 → 第二个工具卡住',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 联系方式
            TextFormField(
              controller: _contactController,
              maxLength: 200,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: '联系方式（可选）',
                hintText: 'QQ / 微信 / 邮箱，方便回复',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // 附带日志开关
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('一并提交近期日志（帮助定位问题）'),
              subtitle: _includeLogs
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('将附带最近 ${_logPreview.length} 条'
                            '（其中 $_warnCount 条 error/warning）'),
                        Text(
                          '日志可能含你最近搜索的关键词和访问的小说信息',
                          style: TextStyle(
                            fontSize: 12,
                            color: appColors.inkSoft,
                          ),
                        ),
                      ],
                    )
                  : const Text('默认关闭，可帮助开发者更快定位'),
              value: _includeLogs,
              onChanged: _submitting ? null : _toggleIncludeLogs,
              secondary: Icon(
                Icons.receipt_long_outlined,
                color:
                    _includeLogs ? appColors.agentAccent : appColors.neutral,
              ),
            ),
            const SizedBox(height: 8),

            // 错误信息
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),

            // 提交按钮
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? '提交中...' : '提交反馈'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}