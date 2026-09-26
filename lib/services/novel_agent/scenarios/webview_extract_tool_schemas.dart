/// WebView 提取场景的工具定义（OpenAI Function Calling schema）
///
/// 从 `WebViewExtractScenario` 抽出的纯静态常量：10 个工具的 function
/// calling 描述。工具名与描述内容是对外行为（LLM 直接消费），
/// 修改前必须确认提示词契约不变。
library;

/// 工具定义常量（OpenAI Function Calling schema）
abstract final class WebViewExtractToolSchemas {
  static const getPageInfoTool = {
    'type': 'function',
    'function': {
      'name': 'get_page_info',
      'description':
          '获取当前浏览器页面的 URL、页面标题、页面类型推断（chapter_list=目录页 / chapter_content=章节内容页 / unknown=未知）和精简后的 DOM 结构。注意：pageType 仅为参考，请结合 DOM 确认。若返回 PAGE_NOT_READY，请稍后重试。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    },
  };

  static const executeJsTool = {
    'type': 'function',
    'function': {
      'name': 'execute_js',
      'description':
          '在当前 WebView 页面中执行 JavaScript 脚本。'
          '支持两种模式：\n'
          '  1. **探测模式**（传 script）：传入 JS 代码探测 DOM 结构或执行新写的提取脚本。'
          '脚本必须包含 {{URL}} 占位符。执行成功后自动注册到 RunStore 并在 __meta.run_id 返回。\n'
          '  2. **重跑模式**（传 run_id）：从 RunStore 加载已注册的脚本执行，零重抄。'
          'run_id 来源：execute_js 的 __meta.run_id、get_cached_script 的 list_run_id/content_run_id。\n'
          '返回值：业务字段平铺到顶层（title/chapters/...），工具元数据在 __meta 内。\n'
          '脚本超时 120 秒会被自动终止（返回 JS_TIMEOUT）。'
          '常见错误码: JS_SYNTAX_ERROR / JS_REFERENCE_ERROR / JS_TYPE_ERROR / SCRIPT_VALIDATION_FAILED / RUN_ID_NOT_FOUND。'
          '请根据返回的 suggestion 字段修正。',
      'parameters': {
        'type': 'object',
        'properties': {
          'script': {
            'type': 'string',
            'description':
                '【探测模式】要执行的 JavaScript 代码。必须包含 {{URL}} 占位符。'
                "格式: (async function(){ const PAGE_URL = '{{URL}}'; ... return JSON.stringify(result); })()",
          },
          'run_id': {
            'type': 'string',
            'description':
                '【重跑模式】RunStore 中的 run_id（exec_xxx 或 db_xxx）。'
                '从 RunStore 加载脚本执行，AI 无需在上下文中保留脚本内容。',
          },
          'test_url': {
            'type': 'string',
            'description':
                '可选。测试用的 URL，会替换脚本中的 {{URL}}。'
                '测试内容脚本时，建议从目录脚本返回的 chapters 数组中取一个 URL 传入。'
                '不填则使用当前浏览器页面 URL。',
          },
        },
      },
    },
  };

  static const getCachedScriptTool = {
    'type': 'function',
    'function': {
      'name': 'get_cached_script',
      'description':
          '查询指定域名是否已有缓存的提取脚本。找到后自动注册到 RunStore 并返回 '
          'list_run_id + content_run_id，**不返回完整脚本内容**（避免占上下文）。'
          '后续可直接 execute_js(run_id=list_run_id) 重跑，零重抄。'
          '若需查看完整内容（调试），用 inspect_script(run_id=...)。\n'
          '返回 JSON 顶层带 `present` / `missing` 列表，列出当前域名哪些脚本类型已有、哪些缺失。'
          'Agent 应按 missing 项精准调用 save_script(script_type=...) 补全，避免重复生成已有脚本。\n'
          '传 `script_type` 可只查询某一种类型（节省 RunStore 槽位与返回体大小）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'domain': {
            'type': 'string',
            'description':
                '要查询的域名（如 www.example.com）。不填则使用当前页面域名。',
          },
          'script_type': {
            'type': 'string',
            'enum': ['chapter_list', 'chapter_content', 'bookshelf'],
            'description':
                '【可选】只查询并返回指定类型的脚本。'
                '不传=按旧语义同时查询所有类型（一次性返回各自 run_id）。'
                'Agent 补缺失时推荐传值：上次结果 missing 列表里的某一项。',
          },
        },
      },
    },
  };

  static const saveScriptTool = {
    'type': 'function',
    'function': {
      'name': 'save_script',
      'description': '保存提取脚本到本地数据库（按脚本类型分次保存，落库前强制试运行验证）。'
          '工作流程：headless WebView 打开 test_url -> 运行 run_id 指向的 JS -> '
          '校验结果结构 -> 若 ocr=true 走 OCR 还原 -> 全部通过才落库。'
          '验证失败时返回诊断信息指导你修改 JS，不落库。'
          '完整提取器需调用两次：一次 script_type=chapter_list，一次 script_type=chapter_content。',
      'parameters': {
        'type': 'object',
        'properties': {
          'domain': {
            'type': 'string',
            'description': '网站域名',
          },
          'run_id': {
            'type': 'string',
            'description': '脚本在 RunStore 中的 run_id（exec_xxx），'
                '从之前 execute_js 调用的 __meta.run_id 获取。'
                '必须是你已测试通过的脚本，save_script 会用它做落库前验证。',
          },
          'script_type': {
            'type': 'string',
            'enum': ['chapter_list', 'chapter_content', 'bookshelf'],
            'description': '保存的脚本类型。chapter_list 返回 {title, cover_url, chapters:[{title,url}]}'
              '（cover_url 字段必填，缺失会被拒绝落库；允许空串表示确实无封面）；'
              'chapter_content 返回 {title, content, font_family}（OCR 模式需 font_family）；'
              'bookshelf 返回 {novels:[{title,url}]}，提取「我的书架/收藏」页的小说列表，'
              'url 为该站小说目录页绝对路径（bookshelf 不适用 OCR，ocr 固定传 false）。',
          },
          'test_url': {
            'type': 'string',
            'description': '验证用页面 URL。chapter_list 用目录页 URL，'
                'chapter_content 用章节内容页 URL。save_script 会真实加载该 URL 跑 JS 做验证。',
          },
          'ocr': {
            'type': 'boolean',
            'description': '该站点是否需要 OCR 后处理（字体反爬）的硬性开关。\n'
                '传 true 的充要条件：脚本返回的文本中出现 PUA 私用区码点（U+E000–F8FF，页面表现是乱码方块）。\n'
                '若页面文本正常可读，必须传 false。\n'
                '传 true 时，save_script 会先扫描文本中是否存在 PUA 码点；若无则直接拒绝落库并返回 reason=ocr_no_pua。\n'
                '判定方法：在脚本探测阶段留意 execute_js 返回值里是否含 PUA 或乱码方块；可用 JS 码点扫描 console.log([...text].some(c => c >= 0xE000 && c <= 0xF8FF))。\n'
'对 chapter_content：还原 content 里的 PUA；'
              '对 chapter_list：还原 title 字段里的 PUA（小说名 + 章名）。'
              'chapter_list 与 chapter_content 的 ocr 各自独立判定，按各自页面是否真有 PUA 传值，'
              '不必一致（典型如番茄小说：目录页 title/chapter.title 是正常汉字传 false，正文页 content 有 PUA 才传 true）。'
              '落库后分别存为该 script_type 的 ocr 标记，互不覆盖。',
          },
          'display_name': {
            'type': 'string',
            'description': '站点自身的名字（用户书页看到的品牌名，如「起点中文网」「番茄小说」）。'
                '从页面 logo / 顶部品牌文案 / title 提取；拿不准就传空串或省略，'
                '前端会回退到 host。save_script 按 script_type 分次调用时，'
                '仅在第一次调用时传本参数（后续分次调用会保留该值不覆盖）。',
          },
        },
        'required': ['domain', 'run_id', 'script_type', 'test_url', 'ocr'],
      },
    },
  };

  static const inspectScriptTool = {
    'type': 'function',
    'function': {
      'name': 'inspect_script',
      'description':
          '查看 RunStore 中某条 run_id 的完整脚本内容。**调试用**，仅在需要时调用。'
          '常见场景：(1) execute_js 失败需要看完整脚本 debug；(2) 想基于已注册脚本改写并重新执行。'
          '注意：返回完整脚本会占用上下文，**非必要时不要调用**。',
      'parameters': {
        'type': 'object',
        'properties': {
          'run_id': {
            'type': 'string',
            'description':
                'RunStore 中的 run_id。'
                '来源：execute_js 的 __meta.run_id、get_cached_script 的 list_run_id/content_run_id。',
          },
        },
        'required': ['run_id'],
      },
    },
  };

  static const listNetworkRequestsTool = {
    'type': 'function',
    'function': {
      'name': 'list_network_requests',
      'description':
          '列出当前页面自加载以来捕获的 AJAX 请求（XHR/fetch），'
          '用于分析网页接口模式、辅助编写章节提取脚本。'
          '返回每条请求的 URL / method / 请求参数（query_params）/ 请求头。'
          '⚠️ 响应体与 POST body 均不采集：若需看返回内容，用 execute_js 读 DOM 或重发请求。'
          '页面跳转后历史自动清空。',
      'parameters': {
        'type': 'object',
        'properties': {
          'url_contains': {
            'type': 'string',
            'description': 'URL 子串过滤（大小写敏感）。如 "chapter"、"/api/"。',
          },
          'method': {
            'type': 'string',
            'description': 'HTTP method 过滤（GET/POST，大小写不敏感）。',
          },
          'since_index': {
            'type': 'integer',
            'description': '只返回 index 大于此值的记录（用于翻页/查增量）。',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回条数，默认 50，上限 100。',
          },
        },
        'required': <String>[],
      },
    },
  };

  static const getScriptLogsTool = {
    'type': 'function',
    'function': {
      'name': 'get_script_logs',
      'description':
          '查询爬虫运行日志的最近 30 条记录（按时间倒序）。'
          '用于诊断"execute_js 能跑通但实际抓取失败"的问题——查看 HeadlessWebView '
          '在阅读器/FAB添加小说/获取书架等真实场景中执行脚本时的错误、超时、空结果等记录。'
          '每条含时间戳、级别、消息摘要（消息中含 domain= 可自行区分站点）。'
          '注意：日志来自真实使用场景（非当前对话），用于定位脚本上线后的问题。',
      'parameters': {
        'type': 'object',
        'properties': {
          'outcome': {
            'type': 'string',
            'enum': ['all', 'success', 'failure'],
            'description':
                '结果筛选。all=全部（默认）；success=只看成功记录；'
                'failure=只看失败/异常记录（warning 及以上级别）。',
          },
        },
      },
    },
  };

  static const listCachedScriptsTool = {
    'type': 'function',
    'function': {
      'name': 'list_cached_scripts',
      'description': '列出所有已保存的提取脚本（按最近使用排序，最多20条）。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    },
  };

  static const navigateToTool = {
    'type': 'function',
    'function': {
      'name': 'navigate_to',
      'description':
          '让 WebView 跳转到指定 URL，等待页面加载完成后返回。'
          '用于从目录页跳转到章节内容页提取正文。'
          '跳转成功后可调用 get_page_info 查看新页面的 DOM 结构。',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '目标 URL（必须是完整的 http/https 地址）',
          },
        },
        'required': ['url'],
      },
    },
  };

  static const getCurrentUrlTool = {
    'type': 'function',
    'function': {
      'name': 'get_current_url',
      'description':
          '查询 WebView 当前实际加载的 URL（不是场景构造时传入的预期 URL）。'
          '返回字段：url=WebView 实际 URL，expected_url=场景预期 URL，matched=两者是否一致。'
          '典型用途：1) navigate_to 之后确认跳转是否生效；2) 排查 Headless WebView URL 不更新的问题；'
          '3) 判断 execute_js 脚本中 {{URL}} 占位符实际会被替换成什么。'
          'Headless 模式下首次调用会自动同步预期 URL 到 Headless WebView。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    },
  };
}
