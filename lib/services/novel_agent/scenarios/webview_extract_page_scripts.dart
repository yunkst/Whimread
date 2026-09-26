/// WebView 提取场景的页面分析 JS 片段
///
/// 从 `WebViewExtractScenario` 抽出的纯静态常量：get_page_info 工具
/// 注入 WebView 执行的 DOM 精简脚本与页面类型推断脚本。
/// 脚本内容是对外行为（影响返回给 LLM 的 DOM/页面类型），勿随意改动。
library;

/// get_page_info 注入 WebView 的页面分析脚本（纯静态）
abstract final class WebViewExtractPageScripts {
  /// 在 WebView 中执行的 DOM 精简脚本
  ///
  /// 移除无关元素（script/style/nav 等），截断长文本，
  /// 返回精简后的 HTML 结构供 LLM 分析。
  static const domSimplifyJs = '''
(function() {
  var clone = document.cloneNode(true);
  // 移除不需要的元素
  var removeTags = ['script','style','link','meta','noscript','svg','img','video','audio','iframe','nav','footer','header','aside'];
  removeTags.forEach(function(tag) {
    clone.querySelectorAll(tag).forEach(function(el) { el.remove(); });
  });
  // 移除广告类
  clone.querySelectorAll('[class*="ad"],[id*="ad"],[class*="banner"],[class*="popup"],[class*="sidebar"]').forEach(function(el) { el.remove(); });
  // 精简 class：只保留前3个
  clone.querySelectorAll('[class]').forEach(function(el) {
    var classes = el.className.split(' ').slice(0, 3).join(' ');
    el.setAttribute('class', classes);
  });
  // 截断过长文本
  var walker = document.createTreeWalker(clone, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    if (walker.currentNode.textContent.length > 200) {
      walker.currentNode.textContent = walker.currentNode.textContent.substring(0, 200) + '...';
    }
  }
  // 截断整体 HTML 长度
  var html = clone.documentElement.outerHTML;
  if (html.length > 15000) {
    html = html.substring(0, 15000) + '\\n... [DOM truncated]';
  }
  return html;
})()
''';

  /// 页面类型推断脚本
  ///
  /// 通过 DOM 特征简单判断是目录页还是章节内容页：
  /// - 大量相同结构链接 + 长列表 → chapter_list
  /// - 少量链接 + 大量长段落 → chapter_content
  /// - 其他 → unknown
  ///
  /// 返回 JSON: `{"pageType": "chapter_list|chapter_content|unknown", "title": "页面title"}`
  static const inferPageTypeJs = r'''
(function() {
  try {
    var title = document.title || '';
    // 统计链接数量
    var links = document.querySelectorAll('a[href]');
    var linkCount = links.length;
    // 统计长段落（>200字符）
    var paragraphs = document.querySelectorAll('p, div');
    var longParaCount = 0;
    var paraSample = [];
    for (var i = 0; i < paragraphs.length && paraSample.length < 5; i++) {
      var text = (paragraphs[i].innerText || '').trim();
      if (text.length > 200) {
        longParaCount++;
        if (paraSample.length < 3) paraSample.push(text.length);
      }
    }
    // 列表标签
    var listItems = document.querySelectorAll('li').length;
    // 简单启发式：
    // 链接密度高 + 段落少 → 目录页
    // 链接少 + 大量长段落 → 章节内容页
    var pageType = 'unknown';
    if (linkCount >= 20 && longParaCount <= 3) {
      pageType = 'chapter_list';
    } else if (longParaCount >= 3 && linkCount < 20) {
      pageType = 'chapter_content';
    } else if (listItems >= 10 && linkCount >= 10) {
      pageType = 'chapter_list';
    }
    return JSON.stringify({pageType: pageType, title: title});
  } catch (e) {
    return JSON.stringify({pageType: 'unknown', title: '', error: e.toString()});
  }
})()
''';
}
