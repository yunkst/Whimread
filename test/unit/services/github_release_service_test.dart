/// GithubReleaseService 通道与排序逻辑测试
///
/// 验证:
/// - stable 通道调用 /releases/latest
/// - preview 通道调用 /releases?per_page=10 并按 created_at desc 客户端排序
/// - draft 永远跳过
/// - stable 通道跳过 prerelease (即便 latest 接口意外返回)
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/github_release_service.dart';

/// 一个最小化的 Dio 桩:按 URL 返回预设的 Response。
class _StubDio implements Dio {
  /// URL 子串 → 返回数据。匹配时按 key 是否出现在 url 中判断。
  final Map<String, dynamic> responses;

  _StubDio(this.responses);

  @override
  Future<Response<T>> get<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress}) async {
    for (final entry in responses.entries) {
      if (path.contains(entry.key)) {
        return Response<T>(
          data: entry.value as T,
          statusCode: 200,
          requestOptions: RequestOptions(path: path),
        );
      }
    }
    throw DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(
        statusCode: 404,
        requestOptions: RequestOptions(path: path),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 构造一个 release JSON
Map<String, dynamic> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  String createdAt = '2026-07-01T00:00:00Z',
}) =>
    {
      'tag_name': tag,
      'name': tag,
      'body': '',
      'published_at': createdAt,
      'created_at': createdAt,
      'prerelease': prerelease,
      'draft': draft,
      'assets': [
        {
          'name': 'app-arm64-v8a-release.apk',
          'size': 100,
          'browser_download_url': 'https://example.com/$tag.apk',
          'content_type': 'application/vnd.android.package-archive',
        }
      ],
    };

void main() {
  group('fetchLatestRelease - stable 通道 (includePrerelease=false)', () {
    test('调用 /releases/latest 并返回稳定版', () async {
      final dio = _StubDio({
        '/releases/latest': _release('v2.0.0', createdAt: '2026-07-18T15:00:00Z'),
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: false);

      expect(result, isNotNull);
      expect(result!.tagName, 'v2.0.0');
    });

    test('stable 通道跳过 prerelease（latest 接口意外返回 prerelease 时）',
        () async {
      final dio = _StubDio({
        '/releases/latest':
            _release('v2.0.0-preview.1', prerelease: true, createdAt: '2026-07-18T18:00:00Z'),
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: false);

      // stable 通道应跳过 prerelease
      expect(result, isNull);
    });
  });

  group('fetchLatestRelease - preview 通道 (includePrerelease=true)', () {
    test('从列表中按 created_at desc 取最新一条（含 prerelease）', () async {
      // 列表顺序故意打乱：stable 在前，preview 在后但 created_at 更晚
      final dio = _StubDio({
        '?per_page=10': [
          _release('v2.0.0', createdAt: '2026-07-18T15:00:00Z'),
          _release('v2.0.0-preview.1',
              prerelease: true, createdAt: '2026-07-18T18:00:00Z'),
          _release('v1.9.34', createdAt: '2026-07-17T09:00:00Z'),
        ],
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: true);

      // 客户端排序后应拿到 created_at 最新的 v2.0.0-preview.1
      expect(result, isNotNull);
      expect(result!.tagName, 'v2.0.0-preview.1');
      expect(result.prerelease, isTrue);
    });

    test('列表全是稳定版时也能拿到最新一条', () async {
      final dio = _StubDio({
        '?per_page=10': [
          _release('v2.0.0', createdAt: '2026-07-18T15:00:00Z'),
          _release('v1.9.34', createdAt: '2026-07-17T09:00:00Z'),
        ],
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: true);

      expect(result, isNotNull);
      expect(result!.tagName, 'v2.0.0');
      expect(result.prerelease, isFalse);
    });

    test('跳过 draft，取最新的非 draft 版本', () async {
      final dio = _StubDio({
        '?per_page=10': [
          _release('v2.0.0', createdAt: '2026-07-18T15:00:00Z'),
          // draft 版本 created_at 最晚，但应被跳过
          _release('v2.0.0-preview.2',
              prerelease: true, draft: true, createdAt: '2026-07-19T10:00:00Z'),
        ],
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: true);

      // draft 被跳过，返回 v2.0.0
      expect(result, isNotNull);
      expect(result!.tagName, 'v2.0.0');
    });

    test('空列表返回 null', () async {
      final dio = _StubDio({
        '?per_page=10': <Map<String, dynamic>>[],
      });
      final service = GithubReleaseService(dio: dio);

      final result = await service.fetchLatestRelease(includePrerelease: true);

      expect(result, isNull);
    });
  });
}
