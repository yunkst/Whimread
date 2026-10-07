/// 媒体全屏预览页 — 全 app 唯一的「看大图」实现
///
/// 收口前散着 6 份局部实现（文字游戏插图 / 聊天画廊 / 缓存管理页 / 角色详情
/// 图集 / 生图测试面板 / 聊天气泡），路由方式、缩放引擎（PhotoView vs
/// InteractiveViewer）、关闭手势、Hero 转场各不相同。本页是唯一入口：
///
/// - 黑底 + [MediaView] fullscreen 分支（PhotoView 缩放由 MediaView 负责）
/// - 单击任意位置关闭；AppBar 另有 X 按钮（双保险）
/// - 多图走 PageView 横滑，标题显示 n / N；单图无标题
/// - 可选 Hero：来源缩略图与本页**初项**同 tag 时播转场；Hero 只挂初项，
///   整条路由不会出现重名 tag（横滑后其余页无 Hero）
/// - [actions] 预留动作位（如后续「重新生成」按钮）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/media/media_view.dart';

class MediaPreviewScreen extends StatefulWidget {
  /// 单图模式
  final String? mediaId;

  /// 多图模式（gallery 构造）
  final List<String> mediaIds;

  /// 起始页（仅多图模式有意义）
  final int initialIndex;

  /// Hero 标签：须与来源缩略图外层 Hero 的 tag 一致才会播转场；null = 不参与
  final String? heroTag;

  /// AppBar 右侧动作位
  final List<Widget> actions;

  const MediaPreviewScreen({
    super.key,
    required this.mediaId,
    this.heroTag,
    this.actions = const [],
  })  : mediaIds = const <String>[],
        initialIndex = 0;

  const MediaPreviewScreen.gallery({
    super.key,
    required this.mediaIds,
    this.initialIndex = 0,
    this.actions = const [],
  })  : mediaId = null,
        heroTag = null;

  /// 单图快捷入口
  static Future<T?> open<T>(
    BuildContext context,
    String mediaId, {
    String? heroTag,
    List<Widget> actions = const [],
  }) =>
      Navigator.of(context).push<T>(MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          mediaId: mediaId,
          heroTag: heroTag,
          actions: actions,
        ),
      ));

  /// 多图画廊快捷入口
  static Future<T?> openGallery<T>(
    BuildContext context,
    List<String> mediaIds, {
    int initialIndex = 0,
  }) =>
      Navigator.of(context).push<T>(MaterialPageRoute(
        builder: (_) => MediaPreviewScreen.gallery(
          mediaIds: mediaIds,
          initialIndex: initialIndex,
        ),
      ));

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late final List<String> _ids;
  late final int _initialIndex;
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _ids = widget.mediaId != null ? <String>[widget.mediaId!] : widget.mediaIds;
    _initialIndex =
        _ids.isEmpty ? 0 : widget.initialIndex.clamp(0, _ids.length - 1);
    _index = _initialIndex;
    _controller = PageController(initialPage: _initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final total = _ids.length;
    // 黑底浅色系统栏；extendBodyBehindAppBar 让图片满屏（AppBar 透明浮在上层，
    // 空白区命中穿透到 body 的点按关闭手势）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: _close,
          ),
          title: total > 1 ? Text('${_index + 1} / $total') : null,
          actions: widget.actions,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: total > 1
              ? PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: _item,
                )
              : _item(context, 0),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int index) {
    final view = MediaView(mediaId: _ids[index], fullscreen: true);
    // Hero 只挂初项：来源缩略图只有一个，其余页挂了也没有对手，还可能
    // 在横滑中制造同 tag 冲突
    if (widget.heroTag != null && index == _initialIndex) {
      return Hero(tag: widget.heroTag!, child: view);
    }
    return view;
  }
}
