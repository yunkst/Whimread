/// Agent 工具定义（OpenAI Function Calling schema）
///
/// 上下文驱动设计：所有工具不再接受 novelId，而是作用于"当前小说"。
/// - `list_novels` 用于发现书架上的小说
/// - `select_novel` 用于切换当前小说
/// - 章节定位使用 `position`（list_chapters 返回的连续 1-based 顺序号），
///   读 / 写 / 创建章节均通过 position 定位，不暴露真实 chapterId
/// - 角色定位使用 `name`（list_characters 返回的名字），不暴露真实 characterId
/// - 章节写入分两类：
///   - create_chapter / rewrite_chapter 走 LLM 生成流程：组合「修改/创作要求 +
///     人物卡 + 写作标签 + AI 作家设定」为提示词，调用 LLM 产出整章正文后入库；
///     只回传元信息，并在聊天窗口渲染跳转入口。
///   - update_chapter_content 走精确字符串替换（oldString→newString，复用 9 重容错
///     匹配器），不调 LLM；适合错别字、段落替换、对话润色等局部修改。
library;

class AgentTools {
  AgentTools._();

  /// 全部工具定义
  static const List<Map<String, dynamic>> allTools = [
    // ===== 小说导航 =====
    _listNovels,
    _selectNovel,
    _createNovel,
    // ===== 章节读取 =====
    _readChapterContent,
    _listChapters,
    _searchInChapters,
    // ===== 章节写入 =====
    _createChapter,
    _updateChapterContent,
    _rewriteChapter,
    _deleteChapter,
    // ===== 角色 =====
    _listCharacters,
    _updateCharacter,
    _createCharacter,
    _deleteCharacter,
    // ===== 设定 / 大纲 =====
    _getBackgroundSetting,
    _updateBackgroundSetting,
    _updateOutline,
    _writeOutline,
    _getOutline,
    // ===== 小说封面 =====
    _setNovelCover,
    // ===== 提示标签 =====
    _listPromptTags,
    _getPromptTag,
    _savePromptTag,
    _deletePromptTag,
    // ===== 文生图/图生视频（ComfyUI）=====
    _listText2ImgModels,
    _createImages,
    _createImageToVideo,
    // ===== 子 Agent =====
    _dispatchSubagent,
  ];

  /// 查找工具定义（带日志）
  ///
  /// [name] 工具名
  /// 返回工具定义 Map，未找到返回 null
  static Map<String, dynamic>? findTool(String name) {
    for (final tool in allTools) {
      if (tool['function']['name'] == name) {
        return tool;
      }
    }
    return null;
  }

  /// 按白名单过滤工具定义（供 SubagentScenario 使用）
  ///
  /// - 自动剔除 `dispatch_subagent`（强制单层嵌套，子 Agent 不能再派子 Agent）
  /// - 忽略不存在的工具名
  /// - 空白名单返回空列表
  static List<Map<String, dynamic>> filterTools(List<String> allowed) {
    final allowedSet = allowed.toSet()..remove('dispatch_subagent');
    if (allowedSet.isEmpty) return const <Map<String, dynamic>>[];
    return allTools
        .where((t) => allowedSet.contains(t['function']['name']))
        .toList(growable: false);
  }

  // ===== 小说导航 =====

  static const _listNovels = {
    'type': 'function',
    'function': {
      'name': 'list_novels',
      'description':
          '列出书架中的所有小说，包括id、标题、作者和简介。'
          'id 是 select_novel 的必填参数。每次新会话开始时建议先调用本工具。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  static const _selectNovel = {
    'type': 'function',
    'function': {
      'name': 'select_novel',
      'description':
          '切换当前工作小说。切换成功后，所有不传 novelId 的工具将作用于该小说，'
          'UI 窗口也会更新展示。\n'
          '使用场景：\n'
          '- 首次对话时选择目标小说\n'
          '- 用户要求"切换到另一本"时\n'
          '- 操作多本小说时切换上下文\n'
          'novelId 来自 list_novels 返回的 id 字段。',
      'parameters': {
        'type': 'object',
        'properties': {
          'novelId': {
            'type': 'integer',
            'description': '目标小说 ID（从 list_novels 获取）',
          },
        },
        'required': ['novelId'],
      },
    },
  };

  static const _createNovel = {
    'type': 'function',
    'function': {
      'name': 'create_novel',
      'description':
          '创建一本新的原创小说并自动切换为当前工作小说。'
          '创建成功后无需再调用 select_novel。\n'
          '使用场景：\n'
          '- 用户要求"新建一本小说"\n'
          '- 用户想从头开始写一本原创小说\n'
          '- 用户需要一本空白小说来组织章节内容',
      'parameters': {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': '小说标题',
          },
          'description': {
            'type': 'string',
            'description': '小说简介（可选）',
          },
        },
        'required': ['title'],
      },
    },
  };

  // ===== 章节读取 =====

  static const _readChapterContent = {
    'type': 'function',
    'function': {
      'name': 'read_chapter_content',
      'description':
          '读取指定章节的完整正文内容。修改章节前应先调用此工具了解当前内容。'
          'position 来自 list_chapters 返回的 position 字段（1-based 顺序号）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'position': {
            'type': 'integer',
            'description':
                '章节在当前小说列表中的位置（1-based）。如不确定，请先调用 list_chapters。',
          },
        },
        'required': ['position'],
      },
    },
  };

  static const _listChapters = {
    'type': 'function',
    'function': {
      'name': 'list_chapters',
      'description':
          '列出当前小说的所有章节目录。返回的每个章节包含 position（1-based 顺序号）、'
          'title、chapterIndex 和 isCached。position 是其他章节操作工具的必填参数。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  static const _searchInChapters = {
    'type': 'function',
    'function': {
      'name': 'search_in_chapters',
      'description':
          '在当前小说所有已缓存章节中搜索包含指定关键词的内容，返回关键词周围约 80 字的'
          '上下文片段（带前后省略号），适合定位特定情节、道具、台词、设定。\n'
          '返回顶层包含 keyword、totalChaptersHit、totalMatches、truncated、'
          'truncatedChapters、count 等统计字段；每章返回 position、chapterTitle、'
          'matchCount、matchedText（关键词回显）和 snippets（采样后的上下文片段）。\n'
          '高频词（如主角名）会命中很多章节，建议用 positionFrom/positionTo 分段查询'
          '（每次 20-50 章），避免单次结果过大；position 来自 list_chapters。\n'
          '服务端对单次返回的章节数和片段数有兜底上限（分别为 50 章 / 每章 3 片段 / 全局 30'
          '片段），超量时通过 truncated / truncatedChapters 标记告知，请缩小范围或换更精确的'
          '关键词后重试。',
      'parameters': {
        'type': 'object',
        'properties': {
          'keyword': {
            'type': 'string',
            'description': '搜索关键词',
          },
          'positionFrom': {
            'type': 'integer',
            'description':
                '可选。搜索起始章节位置（1-based，含），来自 list_chapters 返回的 position。'
                '与 positionTo 配合使用以分段查询长小说。',
          },
          'positionTo': {
            'type': 'integer',
            'description':
                '可选。搜索结束章节位置（1-based，含）。须 >= positionFrom，否则报错。'
                '不传或只传一端时，另一端视为不限制。',
          },
        },
        'required': ['keyword'],
      },
    },
  };

  // ===== 章节写入 =====

  static const _createChapter = {
    'type': 'function',
    'function': {
      'name': 'create_chapter',
      'description':
          '在指定位置创建新章节，由 AI 生成正文内容。\n'
          '本工具会根据「创作要求」、「人物卡」和「写作标签」组合成提示词调用 LLM 生成正文，'
          '然后插入到指定位置（原有章节自动后移）。\n'
          'position 来自 list_chapters 返回的 position 字段（1-based）；'
          '若 position = N+1（N 为当前章节数），则追加到末尾。\n'
          '生成完成后，聊天窗口会出现可点击的跳转入口。',
      'parameters': {
        'type': 'object',
        'properties': {
          'position': {
            'type': 'integer',
            'description':
                '新章节要插入的位置（1-based）。例如 position=3 表示插入为第 3 章，'
                '原第 3 章及之后的章节自动后移。position = N+1 时追加到末尾。',
          },
          'instruction': {
            'type': 'string',
            'description':
                '创作要求（自然语言描述）。说明希望新章节写什么内容，'
                '例如「主角在酒馆遇到神秘老人，获得关键线索」「写一段紧张的追逐戏」。',
          },
          'title': {
            'type': 'string',
            'description': '章节标题。不传时默认使用「第 {position} 章」。',
          },
          'characterNames': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '参与本章的角色名字列表（如 ["李明","张薇"]）。'
                '这些人物的外貌、性格、背景设定将作为创作上下文。不传则不注入人物设定。',
          },
          'tagNames': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '要应用的写作标签名称列表（如 ["赛博朋克","暗黑"]）。'
                '系统会从每个标签随机抽取一条 prompt 文本拼入提示词。不传则不注入标签。',
          },
        },
        'required': ['position', 'instruction'],
      },
    },
  };

  static const _updateChapterContent = {
    'type': 'function',
    'function': {
      'name': 'update_chapter_content',
      'description':
          '对指定章节正文做精确字符串替换（局部修改，不调 LLM）。\n'
          'position 来自 list_chapters。会读取章节原文，把 oldString 替换为 newString 后保存。\n'
          '⚠️ 会覆盖原有内容；建议先用 read_chapter_content 了解当前内容，'
          '从其返回值中逐字复制 oldString（含缩进）。\n'
          '参数说明：\n'
          '- oldString：要被替换的原文片段（必须与 read_chapter_content 返回的内容一致）。\n'
          '- newString：替换后的内容（必须与 oldString 不同）。\n'
          '- replaceAll：可选，默认 false。true 表示替换所有匹配；false 时若 oldString 在正文中出现多次会报 ambiguous_match。\n'
          '失败情况：\n'
          '- oldString 找不到 → not_found。请用 read_chapter_content 返回的原文逐字复制。\n'
          '- oldString 多处且未设 replaceAll=true → ambiguous_match。请补更多上下文行让匹配唯一，或设 replaceAll=true。\n'
          '- 章节未缓存 → not_cached。\n'
          '大范围重写、风格转换、结构调整请改用 rewrite_chapter。',
      'parameters': {
        'type': 'object',
        'properties': {
          'position': {
            'type': 'integer',
            'description': '章节在当前小说列表中的位置（1-based，从 list_chapters 获取）。',
          },
          'oldString': {
            'type': 'string',
            'description': '要被替换的原文片段',
          },
          'newString': {
            'type': 'string',
            'description': '替换后的内容（必须与 oldString 不同）',
          },
          'replaceAll': {
            'type': 'boolean',
            'description': '是否替换所有匹配（默认 false）。',
          },
        },
        'required': ['position', 'oldString', 'newString'],
      },
    },
  };

  static const _rewriteChapter = {
    'type': 'function',
    'function': {
      'name': 'rewrite_chapter',
      'description':
          'AI 重写指定章节的整章正文。\n'
          '本工具不会直接覆盖——它会读取章节原文，结合「修改要求」、「人物卡」和「写作标签」'
          '组合成提示词调用 LLM 重新生成整章正文，生成后自动保存并替换原内容。\n'
          '⚠️ 会覆盖原有内容；建议先用 read_chapter_content 了解当前内容。\n'
          'position 来自 list_chapters。生成完成后，聊天窗口会出现可点击的跳转入口。\n'
          '使用场景：大范围重写、风格转换、结构调整。\n'
          '只想精确改某段（错别字、段落替换、对话润色）请用 update_chapter_content，更省 token 且不跑偏。',
      'parameters': {
        'type': 'object',
        'properties': {
          'position': {
            'type': 'integer',
            'description': '章节在当前小说列表中的位置（1-based，从 list_chapters 获取）。',
          },
          'rewriteInstruction': {
            'type': 'string',
            'description':
                '修改要求（自然语言描述）。说明希望如何改写本章，'
                '例如「把结尾改成开放式结局，增加环境描写」「让对话更紧凑」。',
          },
          'characterNames': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '参与本章的角色名字列表（如 ["李明","张薇"]）。'
                '这些人物的外貌、性格、背景设定将作为重写上下文。不传则不注入人物设定。',
          },
          'tagNames': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '要应用的写作标签名称列表（如 ["赛博朋克","暗黑"]）。'
                '系统会从每个标签随机抽取一条 prompt 文本拼入提示词。不传则不注入标签。',
          },
        },
        'required': ['position', 'rewriteInstruction'],
      },
    },
  };

  static const _deleteChapter = {
    'type': 'function',
    'function': {
      'name': 'delete_chapter',
      'description':
          '删除当前小说的指定章节。\n'
          'position 来自 list_chapters。删除成功后，后续章节的 position 自动前移。\n'
          '⚠️ 破坏性操作：会同时删除章节元数据（novel_chapters）和缓存正文'
          '（chapter_cache），无法恢复。删除前请先与用户确认意图，'
          '建议先用 read_chapter_content 告知用户要删什么。\n'
          '使用场景：\n'
          '- 用户想删除某章（如写错/重写/合并到别章）\n'
          '- 清理重复或明显不满意的章节\n'
          '不适用：删除整本小说请用其他工具（暂无，请告知用户在书架页长按删除）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'position': {
            'type': 'integer',
            'description': '要删除的章节位置（1-based，从 list_chapters 获取）。',
          },
        },
        'required': ['position'],
      },
    },
  };

  // ===== 角色 =====

  static const _listCharacters = {
    'type': 'function',
    'function': {
      'name': 'list_characters',
      'description': '获取当前小说的所有角色信息列表，包括名称、描述等。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  static const _updateCharacter = {
    'type': 'function',
    'function': {
      'name': 'update_character',
      'description':
          '更新当前小说中已有角色的信息。只更新传入的字段，未传入的字段保持不变。'
          'name 来自 list_characters 返回的角色名。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '要更新的角色名称（来自 list_characters）',
          },
          'gender': {
            'type': 'string',
            'description': '性别（如 "男" / "女" / "未知"）',
          },
          'age': {
            'type': 'integer',
            'description': '年龄',
          },
          'occupation': {
            'type': 'string',
            'description': '职业',
          },
          'personality': {
            'type': 'string',
            'description': '性格特点',
          },
          'appearanceFeatures': {
            'type': 'string',
            'description': '外貌特征',
          },
          'bodyType': {
            'type': 'string',
            'description': '身材体型',
          },
          'clothingStyle': {
            'type': 'string',
            'description': '穿衣风格',
          },
          'backgroundStory': {
            'type': 'string',
            'description': '背景经历',
          },
          'aliases': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '别名列表（如 ["小李", "云哥"]）',
          },
          'avatarMediaId': {
            'type': 'string',
            'description': '头像媒体资源ID（图像或视频），由 create_images / create_image_to_video 返回的 mediaId',
          },
        },
        'required': ['name'],
      },
    },
  };

  static const _createCharacter = {
    'type': 'function',
    'function': {
      'name': 'create_character',
      'description':
          '在当前小说中创建一个新角色。name 必填，建议同时填齐外貌、性格、背景等结构化字段，'
          '以便后续写作时作为上下文注入。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '角色名称',
          },
          'gender': {
            'type': 'string',
            'description': '性别（如 "男" / "女" / "未知"）',
          },
          'age': {
            'type': 'integer',
            'description': '年龄',
          },
          'occupation': {
            'type': 'string',
            'description': '职业',
          },
          'personality': {
            'type': 'string',
            'description': '性格特点',
          },
          'appearanceFeatures': {
            'type': 'string',
            'description': '外貌特征',
          },
          'bodyType': {
            'type': 'string',
            'description': '身材体型',
          },
          'clothingStyle': {
            'type': 'string',
            'description': '穿衣风格',
          },
          'backgroundStory': {
            'type': 'string',
            'description': '背景经历',
          },
          'aliases': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '别名列表（如 ["小李", "云哥"]）',
          },
        },
        'required': ['name'],
      },
    },
  };

  static const _deleteCharacter = {
    'type': 'function',
    'function': {
      'name': 'delete_character',
      'description':
          '删除当前小说中指定名字的角色。\n'
          'name 来自 list_characters 返回的角色名。删除后该角色不再出现在角色列表，'
          '也不会再作为写作上下文注入。\n'
          '⚠️ 破坏性操作：会从 characters 表删除该角色记录，无法恢复。'
          '删除前请先与用户确认意图，建议先用 list_characters 告知用户要删谁。\n'
          '使用场景：\n'
          '- 用户想删除多余/重复的角色\n'
          '- 角色已废弃不再需要\n'
          '注意：若该角色出现在已写好的章节正文中，正文字样不会被修改——删除只影响角色卡片数据。'
          '如需改正文请用 update_chapter_content / rewrite_chapter。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '要删除的角色名称（来自 list_characters）',
          },
        },
        'required': ['name'],
      },
    },
  };

  // ===== 设定 / 大纲 =====

  static const _getBackgroundSetting = {
    'type': 'function',
    'function': {
      'name': 'get_background_setting',
      'description':
          '获取当前小说的世界观与背景设定全文。'
          '修改背景设定（update_background_setting）前应先调用本工具了解当前内容，'
          '避免覆盖已有设定。当前小说未设置过背景设定时返回 empty=true 并引导创建。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  static const _updateBackgroundSetting = {
    'type': 'function',
    'function': {
      'name': 'update_background_setting',
      'description':
          '更新当前小说的世界观和背景设定。会替换原有设定，请包含完整内容。',
      'parameters': {
        'type': 'object',
        'properties': {
          'setting': {
            'type': 'string',
            'description': '新的背景设定全文',
          },
        },
        'required': ['setting'],
      },
    },
  };

  static const _setNovelCover = {
    'type': 'function',
    'function': {
      'name': 'set_novel_cover',
      'description': '设置当前小说的封面。先用 create_images（图片）或 '
          'create_image_to_video（视频）生成媒体拿到 mediaId，再把 mediaId 传到这里。'
          '封面接受图片或视频，展示时保持原比例裁剪（不拉伸变形），不会叠加书名文字。'
          '如需清空封面回到默认占位图，mediaId 传 null。',
      'parameters': {
        'type': 'object',
        'properties': {
          'mediaId': {
            'type': ['string', 'null'],
            'description': '由 create_images / create_image_to_video 返回的 mediaId；'
                '传 null 表示清空封面',
          },
        },
        'required': ['mediaId'],
      },
    },
  };

  static const _updateOutline = {
    'type': 'function',
    'function': {
      'name': 'update_outline',
      'description':
          '对当前小说的大纲做精确字符串替换（局部修改）。\n'
          '参数说明：\n'
          '- oldString：要被替换的原文（建议先 get_outline 拿到当前 content，逐字复制其中片段，避免用臆测内容匹配失败）。\n'
          '- newString：替换后的内容（必须与 oldString 不同）。\n'
          '- replaceAll：可选，默认 false。true 表示替换所有匹配；false 时若 oldString 在大纲中出现多次会报 ambiguous_match。\n'
          '失败情况：\n'
          '- oldString 找不到 → not_found。请用 get_outline 返回的原文，逐字复制（含缩进）。\n'
          '- oldString 多处且未设 replaceAll=true → ambiguous_match。请补更多上下文行让匹配唯一，或设 replaceAll=true。\n'
          '- 大纲不存在 → not_found，请改用 write_outline 创建。\n'
          '- 想整篇重写或新建大纲，请改用 write_outline。',
      'parameters': {
        'type': 'object',
        'properties': {
          'oldString': {
            'type': 'string',
            'description': '要被替换的原文片段',
          },
          'newString': {
            'type': 'string',
            'description': '替换后的内容（必须与 oldString 不同）',
          },
          'replaceAll': {
            'type': 'boolean',
            'description': '是否替换所有匹配（默认 false）。',
          },
        },
        'required': ['oldString', 'newString'],
      },
    },
  };

  static const _writeOutline = {
    'type': 'function',
    'function': {
      'name': 'write_outline',
      'description':
          '创建或整篇覆盖当前小说的大纲。会替换原有内容，请传入完整大纲。'
          '大纲不需要标题，内部用当前小说书名兜底。\n'
          '使用场景：\n'
          '- 首次创建大纲\n'
          '- 需要大范围重写（改动较多时比逐段 update_outline 更高效）\n'
          '- 现有大纲结构需要推翻重做\n'
          '只想改其中一小段请用 update_outline。',
      'parameters': {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': '大纲内容（Markdown格式）',
          },
        },
        'required': ['content'],
      },
    },
  };

  static const _getOutline = {
    'type': 'function',
    'function': {
      'name': 'get_outline',
      'description': '获取当前小说的大纲内容。如果存在多个大纲，返回最新的一个。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  // ===== 提示标签 =====

  static const _listPromptTags = {
    'type': 'function',
    'function': {
      'name': 'list_prompt_tags',
      'description':
          '获取写作提示标签列表，支持按分类名筛选或获取全部。'
          '标签按分类分组返回，每个标签仅包含 id、名称和使用场景'
          '（不含提示词正文，以节省上下文）。\n'
          '查看某个标签的完整提示词请用 get_prompt_tag。\n'
          '使用场景：\n'
          '- 用户想查看或了解可用的写作技巧标签\n'
          '- 需要为写作选择合适的标签风格\n'
          '- 想了解某个分类下有哪些标签',
      'parameters': {
        'type': 'object',
        'properties': {
          'categoryName': {
            'type': 'string',
            'description': '分类名称筛选（如"风格"、"场景"、"人物"、"情节"）。不填则返回全部分类及其标签。',
          },
        },
        'required': <String>[],
      },
    },
  };

  static const _getPromptTag = {
    'type': 'function',
    'function': {
      'name': 'get_prompt_tag',
      'description':
          '查看指定标签的完整提示词（promptText）。\n'
          '- 传入 id 精确查看单个标签\n'
          '- 传入 name 按名称查看（大小写无关精确匹配；同名存在多个时一并返回）\n'
          '使用场景：\n'
          '- 已通过 list_prompt_tags 拿到标签 id 或名称，想查看完整提示词\n'
          '- 引用或修改标签前确认其提示词内容',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': '标签 ID（从 list_prompt_tags 获取）',
          },
          'name': {
            'type': 'string',
            'description': '标签名称（大小写无关精确匹配）',
          },
        },
        'required': <String>[],
      },
    },
  };

  static const _savePromptTag = {
    'type': 'function',
    'function': {
      'name': 'save_prompt_tag',
      'description':
          '创建新标签或更新已有标签。\n'
          '- 传入 id 表示更新已有标签（仅更新传入的字段）\n'
          '- 不传 id 表示创建新标签（自动获取排序序号）\n'
          '- 通过分类名指定所属分类（如"风格"、"场景"、"人物"、"情节"）\n'
          '使用场景：\n'
          '- 用户想创建新的写作技巧标签\n'
          '- 用户想修改已有标签的提示词或使用场景描述',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': '已有标签的 ID（从 list_prompt_tags 获取）。不传则创建新标签。',
          },
          'categoryName': {
            'type': 'string',
            'description': '所属分类名称（如"风格"、"场景"、"人物"、"情节"）',
          },
          'name': {
            'type': 'string',
            'description': '标签名称',
          },
          'reason': {
            'type': 'string',
            'description': '使用场景描述（简短一句话，说明何时该用这个标签）',
          },
          'promptText': {
            'type': 'string',
            'description': '标签的完整提示词文本',
          },
        },
        'required': ['categoryName', 'name', 'promptText'],
      },
    },
  };

  static const _deletePromptTag = {
    'type': 'function',
    'function': {
      'name': 'delete_prompt_tag',
      'description':
          '删除指定的提示标签。\n'
          '使用场景：\n'
          '- 用户想删除不再需要的写作技巧标签\n'
          '- 用户想清理重复或错误的标签',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': '要删除的标签 ID（从 list_prompt_tags 获取）',
          },
        },
        'required': ['id'],
      },
    },
  };

  // ===== 文生图（ComfyUI）=====

  static const _listText2ImgModels = {
    'type': 'function',
    'function': {
      'name': 'list_text2img_models',
      'description':
          '获取可用的文生图工作流列表（动漫风/写实等不同画风）。'
          '返回每个工作流的 name（作为 create_images 的 modelName 参数）、'
          '描述、是否默认，以及 promptSkill（提示词写作技巧，含正向/负向提示词'
          '的具体写法建议）。使用 create_images 前建议先调用本工具拿到 promptSkill，'
          '据此撰写正向 prompt 和负向 prompt 会显著提升出图质量。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
    },
  };

  static const _createImages = {
    'type': 'function',
    'function': {
      'name': 'create_images',
      'description':
          '根据提示词生成图片（异步任务，后端 ComfyUI 执行）。\n'
          '本工具会立即提交任务并返回，图片生成需要数十秒。'
          '聊天窗口会出现图片画廊，自动轮询直到出图完成。\n'
          '使用场景：\n'
          '- 用户想看某角色/场景的视觉化呈现\n'
          '- 为章节配插图\n'
          '- 探索人物外貌的具象化\n'
          'modelName 来自 list_text2img_models 的 name 字段；不传则用默认画风。'
          '建议先调用 list_text2img_models 拿到 promptSkill，'
          '据此撰写 prompt 和 negativePrompt 会显著提升出图质量。',
      'parameters': {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description':
                '图片生成提示词（自然语言描述画面，建议含主体、服饰、场景、光影等）。'
                '英文标签效果通常更好，可中英混合。'
                '先调用 list_text2img_models 拿到 promptSkill 可获取针对性的写法建议。',
          },
          'negativePrompt': {
            'type': 'string',
            'description':
                '负向提示词（可选，避免生成你不想要的元素，例如 '
                '"worst quality, extra fingers, blurry, watermark"）。'
                '仅在所选 modelName 的工作流支持负向提示词（工作流 JSON 含独立负向 '
                'CLIPTextEncode 节点并置入「负向提示词在这里替换」占位符）时生效；'
                '未支持的工作流会静默忽略此参数。',
          },
          'count': {
            'type': 'integer',
            'description': '生成张数（1-4，默认 1）。多张图会以画廊形式展示，可左右切换。',
          },
          'modelName': {
            'type': 'string',
            'description':
                '工作流名称（来自 list_text2img_models 的 name，如"动漫风17.5""写实1"）。'
                '不传则使用后端默认工作流。',
          },
        },
        'required': ['prompt'],
      },
    },
  };

  static const _createImageToVideo = {
    'type': 'function',
    'function': {
      'name': 'create_image_to_video',
      'description':
          '根据一张图片 + 提示词生成短视频（异步任务，后端 ComfyUI 执行）。\n'
          '本工具会立即提交任务并返回，视频生成耗时较长。'
          '聊天窗口会出现视频，自动轮询直到生成完成。\n'
          '使用场景：\n'
          '- 让 create_images 生成的静态图片"动起来"\n'
          '- 为某个画面制作动态效果\n'
          'sourceMediaId 是输入图片的 mediaId（来自 create_images 返回的 mediaId，'
          '或用户上传图片的 mediaId）。返回的 videos 数组里每个视频的 mediaId '
          '即后端 task_id，UI 据此渲染并轮询取视频。',
      'parameters': {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description':
                '视频生成提示词（描述希望图片如何运动/变化，例如'
                '"镜头缓慢推进，头发随风飘动，水面泛起涟漪"）。',
          },
          'sourceMediaId': {
            'type': 'string',
            'description':
                '输入图片的 mediaId。来自 create_images 返回结果中的 mediaId，'
                '或用户上传图片的 mediaId。',
          },
          'count': {
            'type': 'integer',
            'description': '生成视频个数（1-2，默认 1）。每个视频独立提交任务。',
          },
          'modelName': {
            'type': 'string',
            'description': '图生视频工作流名称（可选，不传则使用后端默认工作流）。',
          },
        },
        'required': ['prompt', 'sourceMediaId'],
      },
    },
  };

  // ===== 子 Agent =====

  static const _dispatchSubagent = {
    'type': 'function',
    'function': {
      'name': 'dispatch_subagent',
      'description':
          '派出一个子 Agent 独立执行子任务，适用于可拆分的复杂工作（如梳理大量章节的人物关系、'
          '分卷总结大纲）。子 Agent 只能使用 allowed_tools 列表中的工具，无法继续派子 Agent。\n'
          '使用要点：\n'
          '- task 要足够具体，让子 Agent 能独立完成\n'
          '- allowed_tools 只放子 Agent 真正需要的工具\n'
          '- 同一轮可派多个 dispatch_subagent 并行执行\n'
          '- 子 Agent 完成后返回结构化 Markdown 总结',
      'parameters': {
        'type': 'object',
        'properties': {
          'task': {
            'type': 'string',
            'description':
                '交给子 Agent 的任务说明，例如：'
                '"请阅读第1-30章并梳理主要人物关系，输出每个人物的出场章节和关系。"',
          },
          'allowed_tools': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '子 Agent 可调用的工具名白名单。必须从当前可用工具中选择，'
                '不能包含 dispatch_subagent（子 Agent 不能再派子 Agent）。',
          },
        },
        'required': ['task', 'allowed_tools'],
      },
    },
  };
}
