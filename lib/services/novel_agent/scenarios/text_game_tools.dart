/// 文字游戏工具定义（OpenAI Function Calling schema）
///
/// 与场景类分离：schema 是纯数据（常量），场景类只做编排与执行。
/// 工具清单由 [TextGameScenario.tools] 组装。
library;

// ===== 工具定义（OpenAI Function Calling schema）=====

const Map<String, dynamic> narrateToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'narrate',
    'description':
        '输出一段旁白：环境描写、时间过渡、剧情推进，以及角色的动作、'
        '神态、心理等第三人称描写。每段旁白单独调用一次；一回合可多次调用。',
    'parameters': {
      'type': 'object',
      'properties': {
        'text': {
          'type': 'string',
          'description': '旁白正文（放在最后一个参数输出）',
        },
      },
      'required': ['text'],
    },
  },
};

const Map<String, dynamic> speakToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'speak',
    'description':
        '输出一位登场角色的台词。text 只放角色说的话本身（直接引语，'
        '可含语气词/称呼）；该角色的动作、神态、心理描写一律改用 narrate '
        '单独输出，不要混进台词。character 必须是登场角色之一；'
        '每句台词单独调用一次。',
    'parameters': {
      'type': 'object',
      'properties': {
        'character': {
          'type': 'string',
          'description': '说话的角色名（必须在登场角色列表中）',
        },
        'text': {
          'type': 'string',
          'description': '台词正文（放在最后一个参数输出）',
        },
      },
      'required': ['character', 'text'],
    },
  },
};

const Map<String, dynamic> presentChoicesToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'present_choices',
    'description':
        '结束本回合：给玩家提交 2-4 个**关键抉择**选项。每个选项都应导向'
        '明显不同的走向 / 不可逆的代价 / 关系质变；细枝末节（说哪句话、'
        '无关痛痒的小动作）不要拿来问玩家——先继续推进剧情到真正的分岔口。'
        '必须在输出完旁白与台词之后、作为本回合最后一个工具调用；'
        '调用后不要再输出任何内容，等待玩家选择或自由输入。',
    'parameters': {
      'type': 'object',
      'properties': {
        'choices': {
          'type': 'array',
          'description': '2-4 个选项',
          'items': {
            'type': 'object',
            'properties': {
              'label': {
                'type': 'string',
                'description': '选项短标签（行动或走向，16 字以内）',
              },
              'hint': {
                'type': 'string',
                'description': '可选补充说明（后果/风险提示，30 字以内）',
              },
            },
            'required': ['label'],
          },
        },
      },
      'required': ['choices'],
    },
  },
};

/// 【后悔重置】撤回本回合尚未展示给玩家的草稿
///
/// 回合内容等回合结束才一次性展示给玩家——GM 在本回合写作过程中发现
/// 写错（人名写串、与已确立事实矛盾、剧情走偏）时调用它把已写的
/// 旁白/台词/选项撤回，从干净状态重新创作。玩家从未看到过被撤内容，
/// 撤回对体验无损。
const Map<String, dynamic> discardOutputToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'discard_output',
    'description':
        '【后悔重置】撤回你**本回合已经写出、但玩家尚未看到**的内容：'
        '旁白（narrate）、台词（speak）、选项（present_choices）。'
        '回合内容在本回合结束时才一次性展示，所以此刻撤回玩家完全无感。\n'
        '使用场景：写作过程中发现自己写错了——把角色名写错、与已确立的'
        '设定/前文事实矛盾、剧情走偏、台词不符合角色性格。\n'
        '规则：\n'
        '- 撤回后你会"忘掉"这些内容，请重新创作本回合并照常以 '
        'present_choices 收尾；\n'
        '- 已提交的 update_game_state / roll_random_event / '
        'create_scene_image 不受影响（它们是既成事实，不在可撤回范围）；\n'
        '- 仅在确实写错时使用——频繁撤回会浪费额度且可能反复。',
    'parameters': {
      'type': 'object',
      'properties': {
        'count': {
          'type': 'integer',
          'description':
              '撤回最近几条内容（可选）：不传 = 撤回本回合全部已写内容。'
              '只想推翻最后一段旁白/一句台词时传 1。',
        },
      },
    },
  },
};

/// 场景生图工具（仅 imagePolicy == auto 时注入工具面）
const Map<String, dynamic> createSceneImageToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'create_scene_image',
    'description':
        '为当前关键场景生成一幅插图（异步：提交后立即继续输出剧情，'
        '不要等待，不要向玩家提及生成进度；图完成后会自动插入剧情）。'
        '仅在关键场景调用：新地点、重要角色登场、高潮时刻等，不要每回合都调用。',
    'parameters': {
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description':
              '画面描述提示词（英文效果更佳）：场景 + 角色外貌（可参考角色卡'
              ' facePrompts/appearanceFeatures）+ 构图/光影风格。不要包含文字、水印要求。',
        },
        'aspect_ratio': {
          'type': 'string',
          'description': '可选画面比例（如 3:4 / 16:9），仅部分模型生效',
        },
      },
      'required': ['prompt'],
    },
  },
};

/// 状态账本工具：add/remove 条目，目标为具体角色卡 / 玩家卡 / 世界与剧情线
const Map<String, dynamic> updateGameStateToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'update_game_state',
    'description':
        '把重大且持久的变化记录为状态条目（下一轮生效，长期不会遗忘；角色'
        '变化会记入角色卡版本历史）。记录对象三选一：具体角色（传 '
        'character_name）、玩家角色（省略 character_name 与 target）、'
        '世界与剧情线（target="world"：任务/势力动向/未解悬念）。\n'
        '何时记录：致残、突破等级、获得或失去关键物品、立场关系质变、'
        '新任务与主线动向。何时不记录：战斗掉血未倒下、临时情绪波动等'
        '日常琐事。\n'
        '条目一句话（60 字以内）；不再成立的旧条目用 remove_facts 引用'
        '原文划掉。',
    'parameters': {
      'type': 'object',
      'properties': {
        'character_name': {
          'type': 'string',
          'description':
              '要记录的登场角色名（参战名单中，可为别名）。'
              '省略且 target 非 world 时 = 记录玩家角色',
        },
        'target': {
          'type': 'string',
          'enum': ['player', 'world'],
          'description':
              '记录目标：player=玩家角色（默认）；world=世界与剧情线。'
              '传了 character_name 时按角色处理',
        },
        'add_facts': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '新增条目列表（每条一句话，60 字以内）',
        },
        'remove_facts': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '要划掉的既有条目（引用「游戏当前状态」块中的原文或其关键片段）',
        },
        'reason': {
          'type': 'string',
          'description': '发生变化的一句话原因（如「击败风笑天，获得玄重尺」），'
              '记入版本历史便于回溯',
        },
      },
    },
  },
};

/// 概率判定工具：多分支事件按相对权重随机抽取一个结果
const Map<String, dynamic> rollRandomEventToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'roll_random_event',
    'description':
        '概率判定：对剧情中的不确定性分岔（战斗能否获胜、行动能否成功、'
        '机关是否触发、随机遭遇等）按权重随机抽取一个结果。\n'
        'events 列出全部分支（含失败/意外分支）与相对权重，系统归一化后'
        '抽取一个分支返回。weight 只需相对比例正确，不必加总为 100'
        '（如 70 与 30 即七三开）。\n'
        '⚠️ 结果返回后即为既定事实：必须照此推进剧情，不得改写，也不要'
        '重复调用试图换结果。确定性剧情不要调用本工具。',
    'parameters': {
      'type': 'object',
      'properties': {
        'events': {
          'type': 'array',
          'description': '所有可能分支（2-6 个，必须包含失败/意外分支）。'
              'weight 为相对权重（正数，省略视为 1 即等概率）',
          'items': {
            'type': 'object',
            'properties': {
              'label': {
                'type': 'string',
                'description': '分支结果短标签（如「战斗胜利」「机关触发」）',
              },
              'weight': {
                'type': 'number',
                'description': '相对权重（正数，如 70 与 30 表示七三开）',
              },
            },
            'required': ['label'],
          },
        },
        'reason': {
          'type': 'string',
          'description': '一句话说明为什么判定（如「主角强闯山门禁制」），'
              '记入日志便于回溯',
        },
      },
      'required': ['events'],
    },
  },
};

/// 游戏内建角色卡工具：剧情引入新角色时创建（自动加入参战名单）
const Map<String, dynamic> createGameCharacterToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'create_character',
    'description':
        '为剧情引入一位新角色：创建角色卡并自动加入本游戏参战名单'
        '（会记入角色卡版本历史）。创建后即可用 speak 让其说话。'
        '仅在新角色有持续戏份时创建；一次性路人在旁白中带过即可。',
    'parameters': {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description': '角色名',
        },
        'identity': {
          'type': 'string',
          'description': '身份/职业（如「铁匠」「史莱克学院学员」）',
        },
        'personality': {
          'type': 'string',
          'description': '性格特点',
        },
        'appearance': {
          'type': 'string',
          'description': '外貌特征',
        },
        'background': {
          'type': 'string',
          'description': '背景来历',
        },
        'speech_style': {
          'type': 'string',
          'description': '说话风格（口吻/口头禅，保持扮演一致性）',
        },
        'reason': {
          'type': 'string',
          'description': '登场原因（如「剧情第3回合新登场的铁匠」），记入版本历史',
        },
      },
      'required': ['name'],
    },
  },
};
