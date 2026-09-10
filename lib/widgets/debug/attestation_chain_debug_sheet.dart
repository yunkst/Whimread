/// Debug-only modal sheet: capture & inspect Android Key Attestation chain.
///
/// Triggered from settings screen (7-tap on version tile, debug builds only).
/// 目的:让开发者直接在端上看到自己设备的 Key Attestation 链——锚到
/// Google Hardware Attestation Root、还是厂商自签根、还是 Software 级——
/// 据此判断要不要补 OEM 根、或者彻底放弃 attestation 这条线。
///
/// 不注册、不落库、不消耗额度——纯本地 + 一次 challenge HTTP。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class AttestationChainDebugSheet extends StatefulWidget {
  const AttestationChainDebugSheet({super.key});

  /// 以 showModalBottomSheet 弹出。
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AttestationChainDebugSheet(),
    );
  }

  @override
  State<AttestationChainDebugSheet> createState() =>
      _AttestationChainDebugSheetState();
}

class _AttestationChainDebugSheetState extends State<AttestationChainDebugSheet> {
  bool _loading = false;
  String? _error;
  List<_CertInfo> _chain = const [];

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  child: Text('Attestation 证书链调试（debug only）',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '采集一次设备端生成的 attestation 证书链（不注册、不落库、不消耗额度），'
              '与已知 Google 根指纹对照，判断设备是否锚到 Google Hardware Attestation Root。',
              style: TextStyle(fontSize: 12),
            ),
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
                  '采集失败：$_error',
                  style: TextStyle(
                      color: theme.colorScheme.onErrorContainer, fontSize: 12),
                ),
              ),
            ],
            if (_chain.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SummaryCard(certs: _chain),
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
              OutlinedButton.icon(
                onPressed: () {
                  final all = _chain.map((c) => c.pem).join('\n');
                  Clipboard.setData(ClipboardData(text: all));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('全部 PEM 已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_all),
                label: const Text(
                    '复制全部 PEM（可贴到 openssl x509 -text 查看）'),
              ),
            ],
          ],
        ),
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
  const _SummaryCard({required this.certs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = certs.last;
    final matches = top.matchLabel != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('链长度：${certs.length}'),
          const SizedBox(height: 4),
          Text(
            '末端（根）证书指纹：${top.fingerprint}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 6),
          if (matches)
            Text(
              '✓ 匹配：${top.matchLabel}',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              '✗ 不匹配已知 Google 根（可能是厂商自签根 / 软件级）',
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
  // PEM → base64 body (去掉 BEGIN/END 行与空白)
  final body = pem
      .split('\n')
      .where((l) => !l.contains('-----'))
      .join();
  final der = base64Decode(body);
  return sha256.convert(der).toString();
}