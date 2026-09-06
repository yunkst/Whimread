import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/widgets/character/avatar_media.dart';

/// AvatarMedia 占位分支测试。
///
/// 有 mediaId 的渲染分支依赖 MediaView（ConsumerStatefulWidget）+
/// mediaProxyProvider + VideoPlayer/Image 初始化，端到端 widget test 脆弱
/// （见 media_view_video_test 放弃记录），故仅靠 code review 守护。
/// 此处只验证"无 mediaId / 空串 → 姓名首字符占位"这一纯逻辑分支。
void main() {
  testWidgets('mediaId 为 null → 显示姓名首字符占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: AvatarMedia(
              mediaId: null,
              name: '李云',
              genderColor: Colors.blue,
            ),
          ),
        ),
      ),
    );

    expect(find.text('李'), findsOneWidget);
  });

  testWidgets('mediaId 为空串 → 同样显示占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: AvatarMedia(
              mediaId: '',
              name: '张三',
              genderColor: Colors.red,
            ),
          ),
        ),
      ),
    );

    expect(find.text('张'), findsOneWidget);
  });

  testWidgets('姓名为空 → 占位显示 ?', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: AvatarMedia(
              mediaId: null,
              name: '',
              genderColor: Colors.grey,
            ),
          ),
        ),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });
}
