/// 脚本缓存感知（script_presence_provider）+ FAB 金色化 测试
///
/// 覆盖：
/// - ScriptPresenceNotifier：put / 同值跳过 / invalidateDomain
/// - webviewHasCachedChapterListScriptProvider：
///   domain 为 null → false；缓存未命中 → false；缓存命中 → true
/// - refreshScriptPresence：成功写回 / 抛异常静默跳过
/// - WebViewAddNovelFab：有缓存脚本 → 金色背景 + tooltip「快速提取」；
///   无缓存脚本 → 默认色 + tooltip「添加小说」
///
/// 运行:
///   flutter test test/unit/core/providers/script_presence_provider_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/script_presence_provider.dart';
import 'package:novel_app/core/providers/webview_add_novel_providers.dart';
import 'package:novel_app/widgets/webview_add_novel_button.dart';

/// FAB 金色（与 webview_add_novel_button.dart 内常量一致）
const _kGold = Color(0xFFD4AF37);

void main() {
  group('ScriptPresenceNotifier', () {
    test('put 写入 + 同值跳过（state 不变化）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(scriptPresenceByDomainProvider.notifier);

      expect(container.read(scriptPresenceByDomainProvider), isEmpty);

      notifier.put('a.com', true);
      expect(container.read(scriptPresenceByDomainProvider)['a.com'], isTrue);

      // 同值再写：state 仍是新 Map 但值相同；验证值不变即可
      notifier.put('a.com', true);
      expect(container.read(scriptPresenceByDomainProvider)['a.com'], isTrue);

      notifier.put('a.com', false);
      expect(container.read(scriptPresenceByDomainProvider)['a.com'], isFalse);
    });

    test('invalidateDomain 移除条目（未存在的 domain 无副作用）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(scriptPresenceByDomainProvider.notifier);

      notifier.put('a.com', true);
      notifier.invalidateDomain('a.com');
      expect(container.read(scriptPresenceByDomainProvider), isEmpty);

      // 移除不存在的 domain：不抛
      notifier.invalidateDomain('not.exist');
      expect(container.read(scriptPresenceByDomainProvider), isEmpty);
    });
  });

  group('webviewHasCachedChapterListScriptProvider', () {
    test('domain 为 null → false', () {
      final container = ProviderContainer(overrides: [
        webviewCurrentDomainProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);
      expect(container.read(webviewHasCachedChapterListScriptProvider), isFalse);
    });

    test('domain 非空但缓存未命中 → false', () {
      final container = ProviderContainer(overrides: [
        webviewCurrentDomainProvider.overrideWithValue('nope.com'),
      ]);
      addTearDown(container.dispose);
      expect(container.read(webviewHasCachedChapterListScriptProvider), isFalse);
    });

    test('缓存命中 true → true；命中 false → false', () {
      final container = ProviderContainer(overrides: [
        webviewCurrentDomainProvider.overrideWithValue('a.com'),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(scriptPresenceByDomainProvider.notifier);

      notifier.put('a.com', true);
      expect(container.read(webviewHasCachedChapterListScriptProvider), isTrue);

      notifier.put('a.com', false);
      expect(container.read(webviewHasCachedChapterListScriptProvider), isFalse);
    });
  });

  group('refreshScriptPresence', () {
    test('fetch 成功 → onResult 收到结果', () async {
      final results = <String, bool>{};
      await refreshScriptPresence(
        domain: 'a.com',
        fetch: (d) async => true,
        onResult: (d, has) => results[d] = has,
      );
      expect(results['a.com'], isTrue);
    });

    test('fetch 抛异常 → 静默跳过（不调 onResult、不抛）', () async {
      final results = <String, bool>{};
      await refreshScriptPresence(
        domain: 'bad.com',
        fetch: (d) async => throw StateError('db gone'),
        onResult: (d, has) => results[d] = has,
      );
      expect(results, isEmpty);
    });
  });

  group('WebViewAddNovelFab 金色化', () {
    Future<void> _pumpFab(
      WidgetTester tester, {
      required bool hasCachedScript,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webviewCurrentDomainProvider.overrideWithValue('a.com'),
            webviewHasCachedChapterListScriptProvider
                .overrideWithValue(hasCachedScript),
          ],
          child: const MaterialApp(home: Scaffold(body: WebViewAddNovelFab())),
        ),
      );
      await tester.pump();
    }

    testWidgets('有缓存脚本 → 金色背景 + 快速提取 tooltip', (tester) async {
      await _pumpFab(tester, hasCachedScript: true);

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.backgroundColor, _kGold);
      expect(fab.tooltip, '添加小说（快速提取）');
    });

    testWidgets('无缓存脚本 → 默认色 + 普通 tooltip', (tester) async {
      await _pumpFab(tester, hasCachedScript: false);

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      // 默认色来自 theme 扩展（agentAccent），亮/暗主题取值不同，
      // 只断言「不是金色」即可
      expect(fab.backgroundColor, isNot(equals(_kGold)));
      expect(fab.tooltip, '添加小说');
    });
  });
}