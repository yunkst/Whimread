/// 回归测试：APP 更新对话框在下载进行中不可被外部点击 / 系统返回关闭
///
/// 背景 bug：下载中点击对话框外部（遮罩）会 pop 掉 `_AppUpdateDialogState`，
/// 后续进度回调因 `mounted == false` 被跳过，下载完成后的自动安装也不会触发，
/// 表现为「下载到一半点别处，下载白下了，需要重新下载」。
///
/// 修复：`showAppUpdateDialog` 设 `barrierDismissible: false`，并在对话框内用
/// `PopScope` 在 下载中 / 下载完成待安装 / 安装中 三种状态下拦截系统返回。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/app_version.dart';
import 'package:novel_app/services/app_update_service.dart';
import 'package:novel_app/widgets/app_update_dialog.dart';

class _StubUpdateService extends AppUpdateService {
  _StubUpdateService();

  final Completer<bool> downloadCompleter = Completer<bool>();
  final Completer<bool> installCompleter = Completer<bool>();
  int installCallCount = 0;
  int ignoreCallCount = 0;

  @override
  Future<bool> downloadUpdate({
    required AppVersion version,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) =>
      downloadCompleter.future;

  @override
  Future<bool> installUpdate(String version) async {
    installCallCount++;
    return installCompleter.future;
  }

  @override
  Future<void> ignoreVersion(String version) async {
    ignoreCallCount++;
  }
}

AppVersion _fakeVersion() => AppVersion(
      version: '9.9.9',
      downloadUrl: 'https://example.com/novel_app_v9.9.9.apk',
      fileSize: 48 * 1024 * 1024,
      changelog: '修复更新对话框的若干问题',
      createdAt: '2026-09-16T00:00:00Z',
    );

/// 打开对话框（走真实的 showAppUpdateDialog 辅助函数，
/// 以便同时覆盖 barrierDismissible: false 的行为）
Future<void> _openDialog(
  WidgetTester tester,
  _StubUpdateService service,
  List<String> completed,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showAppUpdateDialog(
                  context,
                  version: _fakeVersion(),
                  updateService: service,
                  onUpdateComplete: () => completed.add('done'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 定位包裹 AlertDialog 的 PopScope
PopScope _dialogPopScope(WidgetTester tester) {
  final matches = tester
      .widgetList<PopScope>(
        find.byWidgetPredicate(
          (w) => w is PopScope && w.child is AlertDialog,
        ),
      )
      .toList();
  expect(matches, isNotEmpty, reason: '更新对话框应由 PopScope 包裹');
  return matches.first;
}

void main() {
  testWidgets('初始状态：canPop 为 true，可点「稍后提醒」关闭', (tester) async {
    final service = _StubUpdateService();
    final completed = <String>[];
    await _openDialog(tester, service, completed);

    expect(_dialogPopScope(tester).canPop, isTrue);
    expect(find.text('稍后提醒'), findsOneWidget);

    await tester.tap(find.text('稍后提醒'));
    await tester.pumpAndSettle();

    expect(service.ignoreCallCount, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('初始状态：点击遮罩不关闭（barrierDismissible: false）', (tester) async {
    final service = _StubUpdateService();
    final completed = <String>[];
    await _openDialog(tester, service, completed);

    // 左上角落在对话框外、遮罩上
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('下载中：点击遮罩 / 系统返回都不会关闭，稍后提醒按钮消失', (tester) async {
    final service = _StubUpdateService();
    final completed = <String>[];
    await _openDialog(tester, service, completed);

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    expect(_dialogPopScope(tester).canPop, isFalse);
    expect(find.text('下载中...'), findsOneWidget);
    expect(find.text('稍后提醒'), findsNothing);

    // 点击遮罩
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    // 系统返回（Android 返回键路径）
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('下载完成待安装：仍不可关闭；安装成功后自动关闭并回调', (tester) async {
    final service = _StubUpdateService();
    final completed = <String>[];
    await _openDialog(tester, service, completed);

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    service.downloadCompleter.complete(true);
    await tester.pump();

    // 下载完成 → 自动进入安装流程（等待 install Completer）
    expect(find.text('下载完成'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_dialogPopScope(tester).canPop, isFalse);

    // 安装完成 → 对话框自动关闭
    service.installCompleter.complete(true);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.installCallCount, 1);
    expect(completed, ['done']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('下载失败：回到初始状态，可重新下载', (tester) async {
    final service = _StubUpdateService();
    final completed = <String>[];
    await _openDialog(tester, service, completed);

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    service.downloadCompleter.complete(false);
    await tester.pump();

    // 失败后不再处于下载态：返回键恢复可用，按钮回到「重新下载」入口
    expect(_dialogPopScope(tester).canPop, isTrue);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('下载中...'), findsNothing);
  });
}
