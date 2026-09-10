/// 设备注册与凭证服务。
///
/// 流程（对应后端 /api/v1/devices/*）：
/// 1. [ensureRegistered]：拿 challenge → TEE 生成 attested 密钥（平台通道）
///    → 注册 → 拿设备 JWT 并缓存
/// 2. [authedHeaders]：给 LLM 代理请求附带 `Authorization: Bearer <JWT>`
/// 3. 收到 401（token 过期/无效）时 ApiServiceWrapper 的 401 拦截器经
///    [renewAuthHeaders]→[renewToken] 自动重注册——同 android_id 服务端
///    去重不会重复发额度，只补发新 JWT
///
/// 安全模型：私钥生成于硬件 TEE 且不可导出，JWT 只是 30 天期的会话凭证；
/// 凭证丢失/过期后的重注册都需要真实设备重新通过 attestation。
library;

import 'dart:async';
import 'dart:math';

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

/// /api/v1/devices/me 的展示用快照
class DeviceQuotaInfo {
  final String deviceId;
  final int quotaBalance;
  final String status;
  final bool attestationVerified;

  const DeviceQuotaInfo({
    required this.deviceId,
    required this.quotaBalance,
    required this.status,
    required this.attestationVerified,
  });
}

/// GitHub Star 兑换额度结果（POST /api/v1/devices/star/redeem）。
class StarRedeemResult {
  final int granted;
  final int quotaBalance;
  final String githubLogin;
  final String message;

  const StarRedeemResult({
    required this.granted,
    required this.quotaBalance,
    required this.githubLogin,
    required this.message,
  });
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

  /// APP 启动时恢复本地缓存的 JWT（无网络请求）。
  ///
  /// 空串归一化为 null（getString 缺省返回 ''，不归一会让
  /// [ensureRegistered]/[fetchQuota] 的空值守卫被穿透，发出空 Bearer 请求）。
  Future<void> loadCached() async {
    final token = await PreferencesService.instance.getString(_kDeviceToken);
    _cachedToken = token.isEmpty ? null : token;
  }

  /// 确保持有有效 JWT；有缓存用缓存，否则走注册。
  Future<String> ensureRegistered() async {
    final cached = _cachedToken;
    if (cached != null && cached.isNotEmpty) return cached;
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

  /// 401 自动恢复入口（注入 [ApiServiceWrapper.unauthorizedRecoveryProvider]）。
  ///
  /// 清掉失效缓存后走 [renewToken] 重注册，返回新请求头；
  /// 恢复失败返回 null（调用方放弃重试，让原始 401 照常上抛）。
  Future<Map<String, String>?> renewAuthHeaders() async {
    try {
      final token = await renewToken();
      return {'Authorization': 'Bearer $token'};
    } catch (e) {
      LoggerService.instance.w(
        '设备凭证自动恢复失败: $e',
        category: LogCategory.ai,
        tags: ['device', 'renew'],
      );
      return null;
    }
  }

  /// 业务请求头：`Authorization: Bearer <设备JWT>`
  Future<Map<String, String>> authedHeaders() async {
    final token = await ensureRegistered();
    return {'Authorization': 'Bearer $token'};
  }

  /// 查询当前设备额度（GET /api/v1/devices/me），供设置页额度展示。
  ///
  /// 尽力而为：未配置托管后端 / 未注册 / 请求失败一律返回 null。
  /// 有意不触发注册——纯展示场景不应产生 attestation 副作用。
  Future<DeviceQuotaInfo?> fetchQuota() async {
    if (!kHasBundledBackend) return null;
    final token = _cachedToken;
    if (token == null || token.isEmpty) return null;
    return fetchMeWithToken(token);
  }

  /// 用给定 token 调 /api/v1/devices/me 并解析余额。
  ///
  /// 单测经 [fetchQuota] 不可达（kHasBundledBackend 是编译期常量），
  /// 因此独立暴露，供测试注入 token 直测网络与解析路径。
  @visibleForTesting
  Future<DeviceQuotaInfo?> fetchMeWithToken(String token) async {
    try {
      final Response resp = await _api.dio.get(
        '/api/v1/devices/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return parseMeResponse(resp.data);
    } catch (e) {
      LoggerService.instance.w(
        '查询设备额度失败（不影响使用）: $e',
        category: LogCategory.ai,
        tags: ['device', 'quota'],
      );
      return null;
    }
  }

  /// 解析 /api/v1/devices/me 响应；余额缺失或类型异常时返回 null。
  static DeviceQuotaInfo? parseMeResponse(dynamic data) {
    if (data is! Map) return null;
    final balance = data['quota_balance'];
    if (balance is! int) return null;
    return DeviceQuotaInfo(
      deviceId: data['device_id']?.toString() ?? '',
      quotaBalance: balance,
      status: data['status']?.toString() ?? '',
      attestationVerified: data['attestation_verified'] == true,
    );
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

  /// Android SSAID（Android 8+ 按 APP 签名 + 用户隔离，同签名重装不变；同型号
  /// 不同设备互不撞号）。优先读原生通道 [Settings.Secure.ANDROID_ID]；读不到
  /// 时退回 [DeviceInfoPlugin] 的 `id`（实际是 [Build.ID]，会撞号但比没有好），
  /// 再退化为安装期随机 ID（仅影响"重装识别"，不影响 attestation 强度）。
  Future<String> _androidId() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final id = await _channel.invokeMethod<String>('androidId');
        if (id != null && id.isNotEmpty) return id;
      } on PlatformException {
        // 原生通道未实现（老版本 / 测试环境）→ fallback 到旧逻辑
      }
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
      // 生成 16 位 hex(与 Settings.Secure.ANDROID_ID 形态一致)以通过服务端
      // ANDROID_ID_RE = /^[0-9a-f]{16}$/i 校验。非加密场景,R() 即可。
      final rnd = Random();
      final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
      fallback = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString(_kAndroidId, fallback);
    }
    return fallback;
  }

  Future<String> _appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  // ======================================================================
  // GitHub Star 兑换免费额度
  // ======================================================================

  /// GitHub Star 兑换：校验该账号已给项目点 Star → 每账号一次性补额。
  ///
  /// 后端逻辑见 whimread-backend `/api/v1/devices/star/redeem`：
  /// - 每个 GitHub 账号全局只能兑换一次（换设备/重装都不行）
  /// - 额度发放与流水写入同事务
  ///
  /// 错误以 [DeviceAuthException] 抛出，code 与后端 error_code 一致：
  /// NOT_STARRED / ALREADY_REDEEMED / INVALID_GITHUB_LOGIN /
  /// STAR_REDEEM_RATE_LIMITED / GITHUB_CHECK_FAILED / NO_BACKEND。
  Future<StarRedeemResult> redeemStarQuota(String githubLogin) async {
    if (!kHasBundledBackend) {
      throw DeviceAuthException(
        'NO_BACKEND',
        '未配置托管后端（打包时未注入 BACKEND_BASE_URL）',
      );
    }
    final token = await ensureRegistered();
    try {
      final Response resp = await _api.dio.post(
        '/api/v1/devices/star/redeem',
        data: {'github_login': githubLogin.trim()},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final result = parseStarRedeemResponse(resp.data);
      LoggerService.instance.i(
        'Star 兑换成功: login=${result.githubLogin} '
        'granted=${result.granted} balance=${result.quotaBalance}',
        category: LogCategory.ai,
        tags: ['device', 'star-redeem'],
      );
      return result;
    } on DioException catch (e) {
      throw mapRedeemDioError(e);
    }
  }

  /// 解析 /star/redeem 成功响应；字段缺失时抛 ArgumentError。
  @visibleForTesting
  static StarRedeemResult parseStarRedeemResponse(dynamic data) {
    if (data is! Map) {
      throw ArgumentError('star/redeem 响应不是 JSON 对象: $data');
    }
    final granted = data['granted'];
    final balance = data['quota_balance'];
    if (granted is! int || balance is! int) {
      throw ArgumentError('star/redeem 响应缺少数值字段: $data');
    }
    return StarRedeemResult(
      granted: granted,
      quotaBalance: balance,
      githubLogin: data['github_login']?.toString() ?? '',
      message: data['message']?.toString() ?? '兑换成功',
    );
  }

  /// 把兑换接口的 DioException 映射为带语义 code 的 [DeviceAuthException]。
  ///
  /// 后端错误体统一为 `{"code": <code>, "message": <msg>}`（cloudfunctions/common/errors.js）；
  /// 网络层失败（无响应）映射为 NETWORK。
  @visibleForTesting
  static DeviceAuthException mapRedeemDioError(DioException e) {
    final resp = e.response;
    if (resp == null) {
      return DeviceAuthException('NETWORK', '网络不可用，请检查网络后重试');
    }
    final data = resp.data;
    final rawCode = data is Map
        ? (data['code'] ?? data['error'])?.toString()
        : null;
    final message = data is Map ? data['message']?.toString() : null;
    switch (rawCode) {
      case 'NOT_STARRED':
        return DeviceAuthException(
          rawCode!,
          '未在项目 Star 列表中找到该账号，请先去 GitHub 点 ⭐ Star 再试',
        );
      case 'ALREADY_REDEEMED':
        return DeviceAuthException(rawCode!, '该 GitHub 账号已兑换过免费额度');
      case 'INVALID_GITHUB_LOGIN':
        return DeviceAuthException(
          rawCode!,
          'GitHub 用户名格式不正确（仅字母/数字/连字符）',
        );
      case 'STAR_REDEEM_RATE_LIMITED':
        return DeviceAuthException(rawCode!, '兑换请求过于频繁，请稍后再试');
      case 'GITHUB_CHECK_FAILED':
        return DeviceAuthException(rawCode!, 'GitHub 服务暂时不可用，请稍后再试');
      case 'DEVICE_TOKEN_EXPIRED':
      case 'DEVICE_TOKEN_INVALID':
      case 'DEVICE_TOKEN_MISSING':
        return DeviceAuthException(rawCode!, '设备凭证已失效，请重启应用重新注册');
      default:
        return DeviceAuthException(
          rawCode ?? 'HTTP_${resp.statusCode}',
          message ?? '兑换失败（HTTP ${resp.statusCode}）',
        );
    }
  }
}
