import 'package:flutter/material.dart';

/// 角色性别色板（业务数据色，不随主题变化）
///
/// 男/女/未指定三色固定，亮暗主题一致，故不放进 [ThemeExtension]（无需 lerp），
/// 直接作为常量提供。同时把"性别 → 色"的 switch 收敛到 [of] 一处。
class GenderPalette {
  GenderPalette._();

  /// 男角色色（Material Blue 700）
  static const Color male = Color(0xFF1976D2);

  /// 女角色色（Pink 500）
  static const Color female = Color(0xFFE91E63);

  /// 未指定性别色（Purple 500）
  static const Color unknown = Color(0xFF9C27B0);

  /// 按性别字符串取色，未知值回落到 [unknown]。
  static Color of(String? gender) => switch (gender) {
        '男' => male,
        '女' => female,
        _ => unknown,
      };
}
