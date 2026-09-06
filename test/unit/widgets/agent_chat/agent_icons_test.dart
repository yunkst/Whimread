import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/agent_chat/agent_icons.dart';

void main() {
  test('AgentIcons 所有常量非 null', () {
    expect(AgentIcons.quill, isNotNull);
    expect(AgentIcons.book, isNotNull);
    expect(AgentIcons.clock, isNotNull);
    expect(AgentIcons.dots, isNotNull);
    expect(AgentIcons.fullscreen, isNotNull);
    expect(AgentIcons.fullscreenExit, isNotNull);
    expect(AgentIcons.stop, isNotNull);
    expect(AgentIcons.close, isNotNull);
    expect(AgentIcons.send, isNotNull);
    expect(AgentIcons.plus, isNotNull);
    expect(AgentIcons.layers, isNotNull);
    expect(AgentIcons.edit, isNotNull);
    expect(AgentIcons.arrow, isNotNull);
    expect(AgentIcons.link, isNotNull);
    expect(AgentIcons.wand, isNotNull);
  });
}
