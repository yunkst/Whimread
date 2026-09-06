import 'package:flutter/foundation.dart';
import '../utils/media_markup_parser.dart';

/// ReaderInteractionController
///
/// 职责：
/// - 段落选择逻辑（单击、长按）
/// - 特写模式管理
/// - 选中文本提取
/// - 段落连续性检查
///
/// 使用方式：
/// ```dart
/// final controller = ReaderInteractionController(
///   onStateChanged: () => setState(() {}),
/// );
///
/// controller.handleParagraphTap(index, paragraphs);
/// controller.toggleCloseupMode();
/// ```
class ReaderInteractionController {
  // ========== UI状态回调 ==========
  final VoidCallback _onStateChanged;

  // ========== 内部状态 ==========
  bool _isCloseupMode = false;
  List<int> _selectedParagraphIndices = [];

  // ========== 构造函数 ==========

  ReaderInteractionController({
    required VoidCallback onStateChanged,
  }) : _onStateChanged = onStateChanged;

  // ========== 公开方法 ==========

  /// 处理段落点击
  ///
  /// [index] 段落索引
  /// [paragraphs] 所有段落列表
  void handleParagraphTap(int index, List<String> paragraphs) {
    if (!_isCloseupMode) return;

    // 检查段落是否为媒体标记（插图、视频等），如果是则不允许选择
    if (index < paragraphs.length &&
        MediaMarkupParser.isMediaMarkup(paragraphs[index])) {
      // 媒体标记段落不允许在特写模式下选择
      debugPrint('⚠️ ReaderInteractionController: 媒体标记段落不允许选择 - index:$index');
      return;
    }

    if (_selectedParagraphIndices.contains(index)) {
      _selectedParagraphIndices.remove(index);
      debugPrint('📝 ReaderInteractionController: 取消选择段落 - index:$index');
    } else {
      _selectedParagraphIndices.add(index);
      debugPrint('📝 ReaderInteractionController: 选择段落 - index:$index');
    }

    // 排序
    _selectedParagraphIndices.sort();

    // 检查是否连续
    if (!isConsecutive(_selectedParagraphIndices)) {
      // 如果不连续，只保留当前点击的段落
      debugPrint(
          '⚠️ ReaderInteractionController: 段落不连续，只保留当前点击 - index:$index');
      _selectedParagraphIndices = [index];
    }

    _notifyStateChange();
  }

  /// 处理段落长按
  ///
  /// 长按显示操作菜单，这个方法只返回是否应该显示菜单
  /// 具体的菜单UI由 reader_screen.dart 处理
  bool shouldHandleLongPress(bool isCloseupMode) {
    if (isCloseupMode) {
      debugPrint('⚠️ ReaderInteractionController: 特写模式下不处理长按');
      return false; // 特写模式下不处理长按
    }
    return true;
  }

  /// 切换特写模式
  ///
  /// [clearSelection] 是否清除选择（默认true）
  void toggleCloseupMode({bool clearSelection = true}) {
    _isCloseupMode = !_isCloseupMode;

    if (_isCloseupMode) {
      debugPrint('🎯 ReaderInteractionController: 开启特写模式');
    } else {
      debugPrint('🎯 ReaderInteractionController: 关闭特写模式');
      if (clearSelection) {
        _selectedParagraphIndices.clear();
        debugPrint('🧹 ReaderInteractionController: 已清除段落选择');
      }
    }

    _notifyStateChange();
  }

  /// 清除段落选择
  void clearSelection() {
    if (_selectedParagraphIndices.isNotEmpty) {
      _selectedParagraphIndices.clear();
      debugPrint('🧹 ReaderInteractionController: 清除段落选择');
      _notifyStateChange();
    }
  }

  /// 获取选中的文本
  ///
  /// [paragraphs] 所有段落列表
  /// 返回选中的文本内容，用双空行分隔
  String getSelectedText(List<String> paragraphs) {
    if (_selectedParagraphIndices.isEmpty) {
      debugPrint('⚠️ ReaderInteractionController: 没有选中的段落');
      return '';
    }

    final selectedTexts = <String>[];

    for (final index in _selectedParagraphIndices) {
      if (index < 0 || index >= paragraphs.length) {
        debugPrint(
            '⚠️ ReaderInteractionController: 索引越界 - index:$index, length:${paragraphs.length}');
        continue;
      }

      final paragraph = paragraphs[index];

      // 如果是插图标记，转换为描述性文本
      if (MediaMarkupParser.isMediaMarkup(paragraph)) {
        final markup = MediaMarkupParser.parseMediaMarkup(paragraph).first;
        if (markup.isIllustration) {
          selectedTexts.add('[插图：此处应显示图片内容，taskId: ${markup.id}]');
        } else {
          selectedTexts.add('[${markup.type}：${markup.id}]');
        }
      } else {
        selectedTexts.add(paragraph.trim());
      }
    }

    final result = selectedTexts.join('\n\n'); // 用双空行分隔，保持结构清晰
    debugPrint('📝 ReaderInteractionController: 获取选中文本 - ${result.length}字符');
    return result;
  }

  /// 检查数组是否连续
  ///
  /// [indices] 索引列表
  /// 返回是否连续
  bool isConsecutive(List<int> indices) {
    if (indices.length <= 1) return true;

    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) {
        return false;
      }
    }

    return true;
  }

  // ========== Getters ==========

  /// 是否在特写模式
  bool get isCloseupMode => _isCloseupMode;

  /// 选中的段落索引列表
  List<int> get selectedParagraphIndices =>
      List.unmodifiable(_selectedParagraphIndices);

  /// 是否有选中段落
  bool get hasSelection => _selectedParagraphIndices.isNotEmpty;

  /// 选中段落数量
  int get selectionCount => _selectedParagraphIndices.length;

  // ========== 私有方法 ==========

  /// 通知状态变化
  void _notifyStateChange() {
    _onStateChanged();
  }

  /// 设置特写模式（直接设置，不切换）
  ///
  /// [value] 特写模式状态
  void setCloseupMode(bool value) {
    if (_isCloseupMode != value) {
      _isCloseupMode = value;
      if (!value) {
        _selectedParagraphIndices.clear();
      }
      _notifyStateChange();
      debugPrint('🎯 ReaderInteractionController: 设置特写模式 - $value');
    }
  }

  /// 批量设置选中的段落
  ///
  /// [indices] 段落索引列表
  void setSelectedParagraphIndices(List<int> indices) {
    _selectedParagraphIndices = List.from(indices);
    _notifyStateChange();
    debugPrint('📝 ReaderInteractionController: 批量设置段落选择 - ${indices.length}个');
  }

  /// 添加段落到选择
  ///
  /// [index] 段落索引
  void addParagraphToSelection(int index) {
    if (!_selectedParagraphIndices.contains(index)) {
      _selectedParagraphIndices.add(index);
      _selectedParagraphIndices.sort();
      _notifyStateChange();
      debugPrint('📝 ReaderInteractionController: 添加段落到选择 - index:$index');
    }
  }

  /// 从选择中移除段落
  ///
  /// [index] 段落索引
  void removeParagraphFromSelection(int index) {
    if (_selectedParagraphIndices.remove(index)) {
      _notifyStateChange();
      debugPrint('📝 ReaderInteractionController: 从选择中移除段落 - index:$index');
    }
  }
}
