library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';
import 'package:novel_app/widgets/agent_chat/fab_launch_request_builder.dart';

void main() {
  group('FabLaunchRequestBuilder.build', () {
    test('无脚本 -> draftMessage 含域名与 URL，autoSend', () {
      final req = FabLaunchRequestBuilder.build(
        currentUrl: 'https://a.com/book/123',
        domain: 'a.com',
        oldScript: null,
        reason: FabFailureReason.noScript,
      );
      expect(req.scenarioId, 'webview_extract');
      expect(req.mode, LaunchMode.autoSend);
      expect(req.draftMessage, contains('a.com'));
      expect(req.draftMessage, contains('https://a.com/book/123'));
      expect(req.context['currentUrl'], 'https://a.com/book/123');
      expect(req.context['domain'], 'a.com');
      expect(req.context['oldScript'], isNull);
      expect(req.context['failureReason'], 'noScript');
    });

    test('脚本报错 -> draftMessage 含错误信息', () {
      final req = FabLaunchRequestBuilder.build(
        currentUrl: 'https://a.com/book/123',
        domain: 'a.com',
        oldScript: '(async function(){...})()',
        reason: FabFailureReason.scriptError,
        errorMessage: 'JS_REFERENCE_ERROR: a is not defined',
      );
      expect(req.draftMessage, contains('JS_REFERENCE_ERROR'));
      expect(req.context['oldScript'], '(async function(){...})()');
      expect(req.context['failureReason'], 'scriptError');
    });

    test('脚本空结果 -> draftMessage 引导先判断目录页', () {
      final req = FabLaunchRequestBuilder.build(
        currentUrl: 'https://a.com/book/123',
        domain: 'a.com',
        oldScript: '(async function(){...})()',
        reason: FabFailureReason.emptyResult,
      );
      expect(req.draftMessage, contains('get_page_info'));
      expect(req.draftMessage, contains('目录页'));
      expect(req.context['failureReason'], 'emptyResult');
    });
  });
}
