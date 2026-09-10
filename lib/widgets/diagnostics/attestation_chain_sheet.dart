/// 设置页 → 关于应用 → 7-tap 弹出的 attestation 证书链诊断面板。
///
/// 用途:用户反馈问题时,提供一键诊断入口——手机型号/Android 版本/APP
/// 版本 + attestation 证书链,一键复制完整文本发回开发者,用于判断
/// 设备 attestation 是否锚到 Google 根、是否需要补 OEM 根、还是
/// Software 级 attestation。
///
/// 不注册、不落库、不消耗额度——纯本地 + 一次 challenge HTTP。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/device/device_auth_service.dart';

/// 与 whimread-admin/cloudfunctions/device-auth/lib/attestation-roots.js 同步:
/// Google Hardware Attestation Root 当前对外公开的两根。
const _googleRootFingerprints = <String, String>{
  // RSA-4096 (issued 2022, serial F1C172A699EAF51D)
  'cedb1cb6dc896ae5ec797348bce9286753c2b38ee71ce0fbe34a9a1248800dfc':
      'Google Hardware Attestation Root (RSA-4096, 2022)',
  // ECDSA P-384 (issued 2025, serial 84A9D0297B0EB58AE7FF0E80DE760605)
  '6d9db4ce6c5c0b293166d08986e05774a8776ceb525d9e4329520de12ba4bcc0':
      'Google Hardware Attestation Root (ECDSA P-384, 2025)',
};

class AttestationChainSheet extends StatefulWidget {
  const AttestationChainSheet({super.key});

  /// 以 showModalBottomSheet 弹出。
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AttestationChainSheet(),
    );
  }

  @override
  State<AttestationChainSheet> createState() => _AttestationChainSheetState();
}

class _AttestationChainSheetState extends State<AttestationChainSheet> {
  bool _loading = false;
  String? _error;
  List<_CertInfo> _chain = const [];
  _DeviceInfo? _device;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final package = await PackageInfo.fromPlatform();
    AndroidDeviceInfo? android;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        android = await DeviceInfoPlugin().androidInfo;
      }
    } catch (_) {
      // device_info 不可用(测试环境/极老机型)→ 设备卡片显示 (unknown)
    }
    setState(() {
      _device = _DeviceInfo(
        manufacturer: android?.manufacturer ?? '(unknown)',
        model: android?.model ?? '(unknown)',
        brand: android?.brand ?? '',
        androidRelease: android?.version.release ?? '',
        sdkInt: android?.version.sdkInt ?? 0,
        appVersion: package.version,
        appBuild: package.buildNumber,
      );
    });
  }

  Future<void> _capture() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chain = await DeviceAuthService.instance.captureAttestationChain();
      setState(() {
        _chain = chain.asMap().entries.map((e) {
          final pem = e.value;
          final fp = _fingerprintOfPem(pem);
          return _CertInfo(
            index: e.key,
            pem: pem,
            fingerprint: fp,
            matchLabel: _googleRootFingerprints[fp],
          );
        }).toList();
      });
    } catch (err) {
      setState(() {
        _error = err is DeviceAuthException
            ? '[${err.code}] ${err.message}'
            : err.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _rootVerdict() {
    if (_chain.isEmpty) return null;
    final top = _chain.last;
    return top.matchLabel;
  }

  String _buildDiagnosticText() {
    final d = _device;
    final lines = <String>[
      '=== Whimread 设备安全诊断 ===',
      if (d != null) ...[
        '设备: ${d.manufacturer} ${d.model}${d.brand.isNotEmpty && d.brand != d.manufacturer ? " (brand: ${d.brand})" : ""}',
        'Android: ${d.androidRelease.isNotEmpty ? d.androidRelease : "(?)"} (SDK ${d.sdkInt})',
        'APP: ${d.appVersion} (${d.appBuild})',
      ],
      '采集时间: ${DateTime.now().toIso8601String()}',
      '',
      '证书链长度: ${_chain.length}',
    ];
    if (_chain.isNotEmpty) {
      final top = _chain.last;
      lines.add('末端(根)证书指纹: ${top.fingerprint}');
      if (top.matchLabel != null) {
        lines.add('✓ 匹配: ${top.matchLabel}');
      } else {
        lines.add('✗ 不匹配已知 Google 根(可能是厂商自签根 / Software 级)');
      }
      lines.add('');
      for (final c in _chain) {
        lines.add('[${c.index}] SHA-256: ${c.fingerprint}'
            '${c.matchLabel != null ? " ✓" : ""}');
        lines.add(c.pem);
        lines.add('');
      }
    }
    return lines.join('\n').trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = _rootVerdict();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.security, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('设备安全诊断',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '展示本机的 attestation 证书链与已知 Google 根指纹对照。'
              '遇到安全相关问题时，把这里的诊断文本发给开发者。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_device != null) _DeviceCard(info: _device!),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _capture,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done),
              label: Text(_loading ? '采集中…' : '采集证书链'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '采集失败:$_error',
                  style: TextStyle(
                      color: theme.colorScheme.onErrorContainer, fontSize: 12),
                ),
              ),
            ],
            if (_chain.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SummaryCard(certs: _chain, verdict: verdict),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _chain.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CertCard(cert: _chain[i]),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _buildDiagnosticText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('诊断文本已复制,可粘贴发给开发者'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_all),
                      label: const Text('复制完整诊断'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceInfo {
  final String manufacturer;
  final String model;
  final String brand;
  final String androidRelease;
  final int sdkInt;
  final String appVersion;
  final String appBuild;

  _DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.brand,
    required this.androidRelease,
    required this.sdkInt,
    required this.appVersion,
    required this.appBuild,
  });
}

class _DeviceCard extends StatelessWidget {
  final _DeviceInfo info;
  const _DeviceCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备: ${info.manufacturer} ${info.model}'
              '${info.brand.isNotEmpty && info.brand != info.manufacturer ? " (brand: ${info.brand})" : ""}'),
          const SizedBox(height: 4),
          Text(
            'Android: ${info.androidRelease.isNotEmpty ? info.androidRelease : "(?)"} (SDK ${info.sdkInt})',
          ),
          const SizedBox(height: 4),
          Text('APP: ${info.appVersion} (${info.appBuild})'),
        ],
      ),
    );
  }
}

class _CertInfo {
  final int index;
  final String pem;
  final String fingerprint; // SHA-256 of DER body, lowercase hex
  final String? matchLabel; // 非空表示匹配某已知 Google 根

  _CertInfo({
    required this.index,
    required this.pem,
    required this.fingerprint,
    required this.matchLabel,
  });
}

class _SummaryCard extends StatelessWidget {
  final List<_CertInfo> certs;
  final String? verdict;
  const _SummaryCard({required this.certs, required this.verdict});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = certs.last;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('链长度: ${certs.length}'),
          const SizedBox(height: 4),
          Text(
            '末端(根)证书指纹: ${top.fingerprint}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (verdict != null)
            Text(
              '✓ 匹配: $verdict',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              '✗ 不匹配已知 Google 根(可能是厂商自签根 / Software 级)',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _CertCard extends StatelessWidget {
  final _CertInfo cert;
  const _CertCard({required this.cert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('[${cert.index}]',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cert.fingerprint,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制 PEM',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: cert.pem));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PEM 已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          if (cert.matchLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '✓ ${cert.matchLabel}',
                style: TextStyle(
                    color: Colors.green.shade700, fontSize: 11),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            cert.pem,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

String _fingerprintOfPem(String pem) {
  final body = pem
      .split('\n')
      .where((l) => !l.contains('-----'))
      .join();
  final der = base64Decode(body);
  return sha256.convert(der).toString();
}