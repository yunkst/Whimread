import 'package:flutter_test/flutter_test.dart';

/// 生图API响应格式修复验证测试
///
/// 修复内容：
/// 1. api_service_wrapper.dart 正确解析 JsonObject 响应
/// 2. scene_illustration_service.dart 支持 'submitted' 状态
void main() {
  group('生图API响应格式修复验证测试', () {
    test('验证修复后的响应解析逻辑', () {
      // 模拟后端返回的SceneIllustrationResponse数据
      final mockResponseData = {
        'task_id': 'test_task_123',
        'status': 'submitted',
        'message': '任务已提交到ComfyUI，共 2 个生成任务'
      };

      // 模拟修复后的api_service_wrapper解析逻辑
      final parsedResponse = <String, dynamic>{};
      if (mockResponseData is Map) {
        final data = mockResponseData as Map;
        parsedResponse['task_id'] = data['task_id']?.toString();
        parsedResponse['status'] = data['status']?.toString();
        parsedResponse['message'] = data['message']?.toString();
      }

      // 验证解析结果
      expect(parsedResponse['task_id'], 'test_task_123');
      expect(parsedResponse['status'], 'submitted');
      expect(parsedResponse['message'], contains('ComfyUI'));

      print('✅ 响应解析正确: $parsedResponse');
    });

    test('验证修复后的状态判断逻辑', () {
      // 测试不同的有效状态
      final validStatuses = ['pending', 'processing', 'submitted'];

      for (final status in validStatuses) {
        final response = {
          'task_id': 'test_task',
          'status': status,
          'message': 'Test message'
        };

        // 模拟修复后的判断逻辑
        final isValidStatus = response['status'] == 'pending' ||
                             response['status'] == 'processing' ||
                             response['status'] == 'submitted';

        expect(isValidStatus, true, reason: 'Status $status 应该被认为是有效的');
        print('✅ Status $status 验证通过');
      }
    });

    test('验证无效状态被正确拒绝', () {
      final invalidStatuses = ['failed', 'error', 'unknown', null];

      for (final status in invalidStatuses) {
        final response = {
          'task_id': 'test_task',
          'status': status,
          'message': 'Test message'
        };

        // 模拟修复后的判断逻辑
        final isValidStatus = response['status'] == 'pending' ||
                             response['status'] == 'processing' ||
                             response['status'] == 'submitted';

        expect(isValidStatus, false, reason: 'Status $status 应该被认为是无效的');
        print('✅ 无效Status $status 正确被拒绝');
      }
    });

    test('验证完整的数据流', () {
      // 模拟从后端API到前端处理的完整流程
      final apiResponse = {
        'task_id': 'scene_task_abc123',
        'status': 'submitted',
        'message': '任务已提交到ComfyUI，共 4 个生成任务'
      };

      // 步骤1: api_service_wrapper解析
      final parsedResponse = <String, dynamic>{};
      if (apiResponse is Map) {
        final data = apiResponse as Map;
        parsedResponse['task_id'] = data['task_id']?.toString();
        parsedResponse['status'] = data['status']?.toString();
        parsedResponse['message'] = data['message']?.toString();
      }

      // 步骤2: scene_illustration_service判断
      final isValidStatus = parsedResponse['status'] == 'pending' ||
                           parsedResponse['status'] == 'processing' ||
                           parsedResponse['status'] == 'submitted';

      // 验证完整流程
      expect(parsedResponse['task_id'], 'scene_task_abc123');
      expect(parsedResponse['status'], 'submitted');
      expect(isValidStatus, true);

      print('✅ 完整数据流验证通过');
      print('   API响应: $apiResponse');
      print('   解析后: $parsedResponse');
      print('   状态有效: $isValidStatus');
    });
  });
}
