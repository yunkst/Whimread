import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/webview_providers.dart';

/// WebView 地址栏组件
///
/// 功能：
/// - 显示当前页面 URL
/// - 用户可手动输入网址
/// - 回车/搜索按钮触发加载
/// - 用户正在输入时不同步远端 URL（避免输入抖动）
class WebViewAddressBar extends ConsumerStatefulWidget {
  /// 地址栏聚焦状态变化回调
  final ValueChanged<bool>? onFocusChanged;

  const WebViewAddressBar({super.key, this.onFocusChanged});

  @override
  ConsumerState<WebViewAddressBar> createState() => WebViewAddressBarState();
}

class WebViewAddressBarState extends ConsumerState<WebViewAddressBar> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(webviewCurrentUrlProvider);
    _textController = TextEditingController(text: initial);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  /// 取消地址栏焦点并收起键盘
  ///
  /// 供外部（如父级 WebViewBrowserScreen）在用户点击网页内容时调用，
  /// 让地址栏退出编辑状态。
  void unfocus() {
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // 订阅当前 URL 变化，仅在非聚焦状态下同步（避免用户输入时抖动）
    ref.listen<String>(webviewCurrentUrlProvider, (previous, next) {
      if (!_focusNode.hasFocus && _textController.text != next) {
        _textController.text = next;
        _textController.selection = TextSelection.collapsed(
          offset: next.length,
        );
      }
    });

    return TextField(
      controller: _textController,
      focusNode: _focusNode,
      textInputAction: TextInputAction.go,
      onSubmitted: _onSubmit,
      decoration: InputDecoration(
        hintText: '输入网址或搜索',
        prefixIcon: const Icon(Icons.link, size: 20),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  void _onSubmit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    ref.read(webviewControllerProvider.notifier).loadUrl(trimmed);
    _focusNode.unfocus();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
