import 'package:flutter/material.dart';

import '../media/media_view.dart';

/// 角色头像：根据 [mediaId] 经 [MediaView] 渲染图像/视频。
///
/// - mediaId 为空（null 或空串）→ 显示姓名首字符占位（透明背景，由父级
///   Container 的 genderColor 提供底色）。
/// - mediaId 有值 → MediaView(boxFit: cover) 裁剪填满。视频自动循环静音
///   播放（类似动图），滚出屏幕由 MediaView 的 VisibilityDetector 触发 pause。
///
/// 组件填满父级约束，尺寸由调用方决定：详情页用固定尺寸 Container，
/// 列表用 Expanded。
class AvatarMedia extends StatelessWidget {
  final String? mediaId;
  final String name;
  final Color genderColor;
  final double borderRadius;
  final double fontSize;
  final VoidCallback? onTap;

  const AvatarMedia({
    required this.mediaId,
    required this.name,
    required this.genderColor,
    this.borderRadius = 14,
    this.fontSize = 48,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasMedia = mediaId != null && mediaId!.isNotEmpty;
    if (!hasMedia) {
      return Center(
        child: Text(
          name.isNotEmpty ? name.characters.first : '?',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: genderColor,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: MediaView(
        mediaId: mediaId!,
        boxFit: BoxFit.cover,
        onTap: onTap,
      ),
    );
  }
}
