/// Agent Chat 图标常量集
///
/// 集中所有 emoji 替换与场景图标，便于将来切换到 flutter_svg 时单点替换。
/// 当前用 Material IconData（项目无 flutter_svg 依赖，遵循零新增依赖）。
library;

import 'package:flutter/material.dart';

abstract final class AgentIcons {
  /// 写作场景徽标（替代 emoji ✍️）
  static const IconData quill = Icons.edit;

  /// 书 / 当前小说（替代 emoji 📖）
  static const IconData book = Icons.menu_book;

  /// 时钟（重试倒计时等时间语义）
  static const IconData clock = Icons.access_time;

  /// 菜单（场景切换/配置/历史）
  static const IconData dots = Icons.more_vert;

  /// 全屏
  static const IconData fullscreen = Icons.fullscreen;

  /// 退出全屏
  static const IconData fullscreenExit = Icons.fullscreen_exit;

  /// 停止 / 中断生成
  static const IconData stop = Icons.stop_rounded;

  /// 关闭
  static const IconData close = Icons.close;

  /// 发送
  static const IconData send = Icons.send_rounded;

  /// 附件 / 添加
  static const IconData plus = Icons.add_rounded;

  /// 上下文压缩（替代 emoji 🗂）
  static const IconData layers = Icons.layers_outlined;

  /// 工具调用
  static const IconData edit = Icons.edit_note;

  /// 前往 / 查看章节
  static const IconData arrow = Icons.arrow_forward;

  /// 链接 / WebView URL
  static const IconData link = Icons.link;

  /// 快捷提示 / 魔法
  static const IconData wand = Icons.auto_awesome;
}
