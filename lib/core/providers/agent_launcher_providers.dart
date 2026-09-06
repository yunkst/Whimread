/// Agent 启动器 Provider
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/services/agent_launcher/contextual_agent_launcher.dart';

final contextualAgentLauncherProvider =
    Provider<ContextualAgentLauncher>((ref) {
  return ContextualAgentLauncher(ref);
});
