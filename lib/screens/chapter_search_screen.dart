import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/search_result.dart';
import '../utils/error_helper.dart';
import '../widgets/highlighted_text.dart';
import '../utils/toast_utils.dart';
import '../services/logger_service.dart';
import '../core/providers/chapter_search_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import 'reader_screen.dart';

/// 章节搜索页面 - Riverpod 版本
///
/// 支持在小说章节内容中搜索关键词
/// 使用 Riverpod 管理状态和依赖
class ChapterSearchScreen extends ConsumerStatefulWidget {
  final Novel novel;

  const ChapterSearchScreen({
    super.key,
    required this.novel,
  });

  @override
  ConsumerState<ChapterSearchScreen> createState() =>
      _ChapterSearchScreenState();
}

class _ChapterSearchScreenState extends ConsumerState<ChapterSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // 设置 Novel 参数（延迟到帧构建完成后，避免在 widget 树构建期间修改 provider）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(novelParamProvider.notifier).setNovel(widget.novel);
    });

    // 移除自动搜索监听器 - 改为仅在用户按回车时搜索
    // _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // _onSearchChanged已移除 - 不再需要实时搜索

  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) {
      LoggerService.instance.i(
        '搜索关键词为空，清除搜索状态',
        category: LogCategory.ui,
        tags: ['search', 'chapter', 'clear'],
      );
      ref.read(searchQueryProvider.notifier).clear();
      ref.read(searchStateProvider.notifier).reset();
      return;
    }

    LoggerService.instance.i(
      '开始章节搜索: "$keyword"',
      category: LogCategory.ui,
      tags: ['search', 'chapter', 'start'],
    );

    // 更新searchQueryProvider以触发searchResultsProvider执行搜索
    // isLoading状态由build方法中的ref.listen自动管理
    ref.read(searchQueryProvider.notifier).update(keyword);
    ref.read(searchStateProvider.notifier).setHasSearched(true);
    ref.read(searchStateProvider.notifier).setIsLoading(true);

    LoggerService.instance.d(
      '搜索状态已更新: isLoading=true, hasSearched=true',
      category: LogCategory.ui,
      tags: ['search', 'state'],
    );
  }

  void _clearSearch() {
    LoggerService.instance.i(
      '清除搜索',
      category: LogCategory.ui,
      tags: ['search', 'chapter', 'clear'],
    );

    _searchController.clear();
    ref.read(searchQueryProvider.notifier).clear();
    ref.read(searchStateProvider.notifier).reset();
  }

  /// 构建所有匹配项的高亮显示
  List<Widget> _buildMatchHighlights(ChapterSearchResult result) {
    if (result.matchPositions.isEmpty) {
      return const [
        SizedBox.shrink(),
      ];
    }

    return result.matchPositions.map((position) {
      // 提取匹配位置前后的上下文（前后20字）
      final start = (position.start - 20).clamp(0, result.content.length);
      final end = (position.end + 20).clamp(0, result.content.length);
      var contextText = result.content.substring(start, end);

      // 添加省略号
      if (start > 0) contextText = '...$contextText';
      if (end < result.content.length) contextText = '$contextText...';

      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _SingleMatchHighlight(
          text: contextText,
          keywords: result.searchKeywords,
          style: AppTypography.bodyProse.copyWith(
            fontSize: 14,
            height: 1.4,
            color: context.appColors.ink,
          ),
        ),
      );
    }).toList();
  }

  Chapter? _findChapterByUrl(
    List<Chapter> chapters,
    String chapterUrl,
  ) {
    try {
      return chapters.firstWhere((chapter) => chapter.url == chapterUrl);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听搜索状态
    final searchState = ref.watch(searchStateProvider);

    // 监听搜索结果
    final searchResultsAsync = ref.watch(searchResultsProvider);

    // 监听章节列表
    final chaptersAsync = ref.watch(chaptersListProvider);

    // 当searchQuery更新且不为空时，自动开始搜索并设置loading
    // 当searchResultsProvider完成时，自动清除loading
    ref.listen<AsyncValue<List<ChapterSearchResult>>>(
      searchResultsProvider,
      (previous, next) {
        // 如果搜索完成（无论是成功还是失败），都清除loading状态
        if (searchState.isLoading) {
          if (next.hasValue || next.hasError) {
            LoggerService.instance.i(
              '章节搜索完成，清除loading状态',
              category: LogCategory.ui,
              tags: ['search', 'chapter', 'complete'],
            );

            if (next.hasError) {
              LoggerService.instance.e(
                '章节搜索失败: ${next.error}',
                stackTrace: next.stackTrace?.toString(),
                category: LogCategory.ui,
                tags: ['search', 'chapter', 'error'],
              );
            } else if (next.value != null) {
              LoggerService.instance.i(
                '章节搜索成功，找到 ${next.value!.length} 个结果',
                category: LogCategory.ui,
                tags: ['search', 'chapter', 'success'],
              );
            }

            ref.read(searchStateProvider.notifier).setIsLoading(false);
          }
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '搜索章节内容',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          if (searchState.hasSearched)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
              tooltip: '清除搜索',
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索 ${widget.novel.title} 的章节内容...',
                hintStyle: TextStyle(color: context.appColors.inkSoft),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: context.appColors.paper,
              ),
              style: AppTypography.bodyProse.copyWith(
                fontSize: 15,
                height: 1.4,
                color: context.appColors.ink,
              ),
              onSubmitted: _performSearch,
            ),
          ),

          // 搜索结果
          Expanded(
            child: _buildSearchResults(
              context,
              searchState,
              searchResultsAsync,
              chaptersAsync,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    SearchStateData searchState,
    AsyncValue<List<ChapterSearchResult>> searchResultsAsync,
    AsyncValue<List<Chapter>> chaptersAsync,
  ) {
    // 显示加载中
    if (searchState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在搜索...',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
          ],
        ),
      );
    }

    // 显示初始提示
    if (!searchState.hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: context.appColors.inkSoft.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索章节内容',
              style: AppTypography.bodyProse.copyWith(
                fontSize: 16,
                color: context.appColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持搜索章节标题和内容',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    // 显示搜索结果或错误
    return searchResultsAsync.when(
      loading: () {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
      data: (searchResults) {
        // 无结果
        if (searchResults.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: context.appColors.inkSoft.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  '未找到相关内容',
                  style: AppTypography.bodyProse.copyWith(
                    fontSize: 16,
                    color: context.appColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '尝试使用其他关键词',
                  style: AppTypography.metaItalic.copyWith(
                    color: context.appColors.inkSoft.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '提示：可以搜索章节标题或内容',
                  style: AppTypography.metaItalic.copyWith(
                    color: context.appColors.inkSoft.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        }

        // 显示结果列表
        return chaptersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          data: (chapters) {
            return ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final result = searchResults[index];
                final chapter = _findChapterByUrl(chapters, result.chapterUrl);

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  elevation: 2,
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: result.matchPositions.isNotEmpty
                              ? TitleHighlight(
                                  title: result.chapterTitle,
                                  keywords: result.searchKeywords,
                                  style: AppTypography.novelTitle.copyWith(
                                    fontSize: 16,
                                  ),
                                )
                              : Text(
                                  result.chapterTitle,
                                  style: AppTypography.novelTitle.copyWith(
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        if (result.matchCount > 0)
                          Text(
                            ' (${result.matchCount}处匹配)',
                            style: AppTypography.metaItalic.copyWith(
                              color: context.appColors.inkSoft,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 匹配的文本片段列表（带高亮）
                        ..._buildMatchHighlights(result),

                        // 缓存时间
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '缓存于 ${result.cachedAt.toString().substring(0, 19).replaceAll('-', '/')}',
                            style: AppTypography.metaItalic.copyWith(
                              color: context.appColors.inkSoft.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (chapter != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReaderScreen(
                              novel: widget.novel,
                              chapter: chapter,
                              chapters: chapters,
                              // 传递搜索结果以便精确跳转
                              searchResult: result,
                            ),
                          ),
                        );
                      } else {
                        LoggerService.instance.e(
                          '无法打开章节: Chapter not found for URL: ${result.chapterUrl}',
                          category: LogCategory.database,
                          tags: ['chapter', 'open', 'not-found'],
                        );
                        ToastUtils.show('无法打开该章节');
                      }
                    },
                  ),
                );
              },
            );
          },
          error: (error, stack) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: context.appColors.error.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载章节列表失败',
                    style: AppTypography.bodyProse.copyWith(
                      fontSize: 16,
                      color: context.appColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: AppTypography.metaItalic.copyWith(
                      color: context.appColors.inkSoft.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
      error: (error, stack) {
        ErrorHelper.showErrorWithLog(
          context,
          '搜索失败',
          stackTrace: stack,
          category: LogCategory.database,
          tags: ['chapter', 'search', 'failed'],
        );
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: context.appColors.error.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              Text(
                '搜索失败',
                style: AppTypography.bodyProse.copyWith(
                  fontSize: 16,
                  color: context.appColors.inkSoft,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: AppTypography.metaItalic.copyWith(
                  color: context.appColors.inkSoft.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个匹配高亮组件
class _SingleMatchHighlight extends StatelessWidget {
  final String text;
  final List<String> keywords;
  final TextStyle? style;

  const _SingleMatchHighlight({
    required this.text,
    required this.keywords,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: style,
        children: _buildHighlightedSpans(context),
      ),
    );
  }

  List<TextSpan> _buildHighlightedSpans(BuildContext context) {
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    // 查找所有关键词的匹配位置
    final List<MatchPosition> allMatches = [];
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      final pattern = RegExp(RegExp.escape(keyword), caseSensitive: false);
      for (final match in pattern.allMatches(text)) {
        allMatches.add(MatchPosition(
          start: match.start,
          end: match.end,
          matchedText: match.group(0) ?? '',
        ));
      }
    }

    // 按位置排序
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // 构建高亮的文本片段
    for (final match in allMatches) {
      // 添加匹配前的普通文本
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
        ));
      }

      // 添加高亮的匹配文本
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          fontWeight: FontWeight.bold,
        ),
      ));

      currentIndex = match.end;
    }

    // 添加剩余的普通文本
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
      ));
    }

    return spans;
  }
}
