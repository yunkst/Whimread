/// 设备注册与凭证服务。
///
/// 流程（对应后端 /api/v1/devices/*）：
/// 1. [ensureRegistered]：拿 challenge → TEE 生成 attested 密钥（平台通道）
///    → 注册 → 拿设备 JWT 并缓存
/// 2. [authedHeaders]：给 LLM 代理请求附带 `Authorization: Bearer <JWT>`
/// 3. 收到 401（token 过期/无效）时调用 [renewToken]——同 android_id 重注册，
///    服务端去重不会重复发额度，只补发新 JWT
///
/// 安全模型：私钥生成于硬件 TEE 且不可导出，JWT 只是 30 天期的会话凭证；
/// 凭证丢失/过期后的重注册都需要真实设备重新通过 attestation。
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/build_config.dart';
import '../api_service_wrapper.dart';
import '../logger_service.dart';
import '../preferences_service.dart';

/// 设备注册/鉴权异常
class DeviceAuthException implements Exception {
  final String code;
  final String message;

  DeviceAuthException(this.code, this.message);

  @override
  String toString() => 'DeviceAuthException($code): $message';
}

class DeviceAuthService {
  DeviceAuthService._();

  static final DeviceAuthService instance = DeviceAuthService._();

  ApiServiceWrapper? _apiOverride;

  /// 测试/特殊场景注入自定义 wrapper；默认走全局单例
  void useWrapper(ApiServiceWrapper wrapper) => _apiOverride = wrapper;

  ApiServiceWrapper get _api => _apiOverride ?? ApiServiceWrapper();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static const MethodChannel _channel = MethodChannel(
    'com.example.novel_app/device',
  );

  static const String _kDeviceToken = 'device_jwt';
  static const String _kAndroidId = 'device_android_id_fallback';

  String? _cachedToken;

  /// 当前可用 token（null = 尚未注册）
  String? get cachedToken => _cachedToken;

  /// APP 启动时恢复本地缓存的 JWT（无网络请求）
  Future<void> loadCached() async {
    _cachedToken = await PreferencesService.instance.getString(_kDeviceToken);
  }

  /// 确保持有有效 JWT；有缓存用缓存，否则走注册。
  Future<String> ensureRegistered() async {
    final cached = _cachedToken;
    if (cached != null) return cached;
    return register();
  }

  /// 注册设备：challenge → attestation → 后端验链发 JWT（同设备去重）。
  Future<String> register() async {
    if (!kHasBundledBackend) {
      throw DeviceAuthException(
        'NO_BACKEND',
        '未配置托管后端（打包时未注入 BACKEND_BASE_URL）',
      );
    }
    final dio = _api.dio;

    // 1. challenge（一次性，120 秒有效）
    final Response challengeResp = await dio.post('/api/v1/devices/challenge');
    final nonce = challengeResp.data['nonce'] as String?;
    if (nonce == null || nonce.isEmpty) {
      throw DeviceAuthException('CHALLENGE_INVALID', '服务器未返回有效 challenge');
    }

    // 2. 本地 TEE 生成 attested 密钥 + 证书链（Android 平台通道）
    final chain = await _attest(nonce);
    if (chain.isEmpty) {
      throw DeviceAuthException('ATTESTATION_EMPTY', '平台未返回证书链');
    }

    // 3. 注册
    final Response registerResp = await dio.post(
      '/api/v1/devices/register',
      data: {
        'android_id': await _androidId(),
        'platform': 'android',
        'app_version': await _appVersion(),
        'challenge': nonce,
        'certificate_chain_pem': chain,
      },
    );
    final data = registerResp.data as Map;
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw DeviceAuthException('REGISTER_FAILED', '服务器未返回设备凭证');
    }

    // 4. 缓存 JWT
    _cachedToken = token;
    await PreferencesService.instance.setString(_kDeviceToken, token);

    LoggerService.instance.i(
      '设备注册成功: id=${data['device_id']} '
      'attested=${data['attestation_verified']} quota=${data['quota_balance']}',
      category: LogCategory.ai,
      tags: ['device', 'register'],
    );
    return token;
  }

  /// token 失效后的恢复：走完整重注册（同 android_id 服务端去重，不重复发额度）。
  Future<String> renewToken() async {
    LoggerService.instance.i(
      '设备 token 失效，重新注册换取新凭证',
      category: LogCategory.ai,
      tags: ['device', 'renew'],
    );
    _cachedToken = null;
    return register();
  }

  /// 业务请求头：`Authorization: Bearer <设备JWT>`
  Future<Map<String, String>> authedHeaders() async {
    final token = await ensureRegistered();
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<String>> _attest(String challenge) async {
    try {
      final chain = await _channel.invokeMethod<List<dynamic>>('attest', {
        'challenge': challenge,
      });
      return chain?.cast<String>() ?? const [];
    } on PlatformException catch (e) {
      throw DeviceAuthException(
        e.code,
        '设备 attestation 失败: ${e.message ?? e.code}',
      );
    }
  }

  /// Android SSAID（Android 8+ 按 APP 签名隔离，同签名重装不变）；
  /// 读取失败退化为安装期随机 ID（仅影响“重装识别”，不影响 attestation 强度）。
  Future<String> _androidId() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final info = await _deviceInfo.androidInfo;
        final id = info.id;
        if (id.isNotEmpty) return id;
      } on PlatformException {
        // fallthrough to fallback
      }
    }
    final prefs = PreferencesService.instance;
    var fallback = await prefs.getString(_kAndroidId);
    if (fallback.isEmpty) {
      fallback = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await prefs.setString(_kAndroidId, fallback);
    }
    return fallback;
  }

  Future<String> _appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
