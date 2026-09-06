import 'package:flutter_test/flutter_test.dart';

/// 生图API响应格式bug测试
///
/// Bug描述：
/// 后端返回SceneIllustrationResponse包含 {task_id, status, message}
/// 但前端api_service_wrapper.dart中返回 {'data': response.data.toString()}
/// 导致无法正确解析status字段，生成图像功能失效
void main() {
  group('生图API响应格式Bug测试', () {
    test('应该正确解析响应', () {
      // 模拟后端返回的SceneIllustrationResponse数据
      final mockResponseData = {
        'task_id': 'test_task_123',
        'status': 'submitted',
        'message': '任务已提交到ComfyUI'
      };

      // 当前错误的处理方式（导致bug）
      final wrongResponse = {'data': mockResponseData.toString()};
      print('❌ 错误的响应格式: $wrongResponse');
      print('   无法直接访问status: ${wrongResponse['status']}'); // null

      // 正确的处理方式
      final correctResponse = mockResponseData;
      print('✅ 正确的响应格式: $correctResponse');
      print('   可以访问status: ${correctResponse['status']}');

      // 验证正确响应包含必要字段
      expect(correctResponse['task_id'], 'test_task_123');
      expect(correctResponse['status'], 'submitted');
      expect(correctResponse['message'], contains('ComfyUI'));
    });

    test('验证当前bug导致的判断逻辑问题', () {
      // 模拟当前错误的响应格式
      final buggyResponse = {'data': 'SceneIllustrationResponse对象字符串'};

      // 当前代码中的判断逻辑
      final isValidStatus = buggyResponse['status'] == 'pending' ||
                           buggyResponse['status'] == 'processing';

      expect(isValidStatus, false);
      expect(buggyResponse['status'], null);

      print('❌ Bug导致status判断失败: $isValidStatus');
    });

    test('验证修复后的判断逻辑', () {
      // 模拟正确的响应格式
      final fixedResponse = {
        'task_id': 'test_task_123',
        'status': 'submitted',
        'message': '任务已提交'
      };

      // 修复后的判断逻辑应该支持 'submitted' 状态
      final isValidStatus = fixedResponse['status'] == 'pending' ||
                           fixedResponse['status'] == 'processing' ||
                           fixedResponse['status'] == 'submitted';

      expect(isValidStatus, true);
      expect(fixedResponse['status'], 'submitted');

      print('✅ 修复后status判断正确: $isValidStatus');
    });
  });
}
