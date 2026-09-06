import 'dart:async';
import 'dart:collection';
import '../models/chapter.dart';
import 'rate_limiter.dart';
import 'preload_task.dart';
import 'preload_progress_update.dart';
import 'preload_history_entry.dart';
import '../repositories/chapter_repository.dart';
import 'headless_webview_content_service.dart';
import 'headless_webview_errors.dart';
import 'logger_service.dart';

/// 全局预加载服务
///
/// 负责管理章节预加载任务队列，支持：
/// - 智能排序：当前章节之后（后续章节）优先，当前章节之前（前序章节）次之
/// - 抢占恢复：被阅读器抢占的任务放回队头，等待恢复后立即执行
/// - 速率限制：缓存命中立即执行，爬虫抓取 30 秒间隔
/// - 串行执行：全局唯一执行点，避免 WebView 资源竞争
/// - 去重机制：自动过滤队列内重复 URL 和已缓存章节
/// - 内存队列：App 关闭自动清空
/// - 暂停/恢复：阅读器请求优先时可暂停预加载，释放 WebView
///
/// 架构说明：
/// - 使用依赖注入，通过 Riverpod Provider 管理
/// - ChapterRepository 和 HeadlessWebViewContentService 通过构造函数注入
/// - 通过 @Riverpod(keepAlive: true) 全局单例，App 生命周期内不销毁
class PreloadService {
  // 核心组件
  final RateLimiter _rateLimiter = RateLimiter(interval: Duration(seconds: 30));

  /// 有序任务队列（FIFO，支持 addFirst 抢占恢复）
  final ListQueue<PreloadTask> _queue = ListQueue<PreloadTask>();

  /// 去重集合：已入队的 chapterUrl（仅用于 O(1) 判断重复）
  final Set<String> _enqueuedUrls = <String>{};

  // 历史记录上限（避免内存膨胀）
  static const int _historyLimit = 100;

  /// 已处理（成功）历史，最新在前
  final List<PreloadHistoryEntry> _processedHistory = [];

  /// 已失败历史，最新在前
  final List<PreloadHistoryEntry> _failedHistory = [];

  // 进度通知（供章节列表页面实时更新缓存状态）
  final StreamController<PreloadProgressUpdate> _progressController =
      StreamController<PreloadProgressUpdate>.broadcast();

  Stream<PreloadProgressUpdate> get progressStream =>
      _progressController.stream;

  // 小说状态跟踪
  final Map<String, int> _novelCurrentIndex = {}; // novelUrl -> 当前阅读章节索引
  String? _lastActiveNovel; // 最后活跃的小说URL

  // 执行状态
  bool _isRunning = false; // 🔒 串行锁：确保同一时间只有一个处理循环
  bool _shouldStop = false; // 停止标志（用于测试清理）
  bool _isPaused = false; // 暂停标志（阅读器请求优先时设置）
  int _totalProcessed = 0;
  int _totalFailed = 0;

  /// 当前正在处理的任务（供 UI 展示处理状态详情）
  PreloadTask? _currentTask;
  PreloadTask? get currentTask => _currentTask;

  // 服务依赖（通过构造函数注入）
  final ChapterRepository _chapterRepository;
  final HeadlessWebViewContentService? _headlessService;

  /// 构造函数
  ///
  /// 通过依赖注入接收 ChapterRepository 和 HeadlessWebViewContentService
  PreloadService({
    required ChapterRepository chapterRepository,
    HeadlessWebViewContentService? headlessService,
  })  : _chapterRepository = chapterRepository,
        _headlessService = headlessService {
    _logInitialization();
  }

  /// 记录初始化日志
  void _logInitialization() {
    LoggerService.instance.i(
      'PreloadService初始化完成',
      category: LogCategory.cache,
      tags: ['preload', 'init'],
    );
  }

  /// 添加预加载任务
  ///
  /// 新任务追加到队尾（addLast），不插队。仅被阅读器抢占的任务
  /// 才会通过 addFirst 放回队头，保证恢复后立即继续执行。
  ///
  /// [novelUrl] 小说URL
  /// [novelTitle] 小说标题
  /// [chapterUrls] 所有章节URL列表
  /// [currentIndex] 当前阅读章节的索引
  Future<void> enqueueTasks({
    required String novelUrl,
    required String novelTitle,
    required List<String> chapterUrls,
    required int currentIndex,
  }) async {
    // 更新小说状态
    _novelCurrentIndex[novelUrl] = currentIndex;
    _lastActiveNovel = novelUrl;

    // 使用ChapterRepository的批量检查方法
    final uncachedUrls =
        await _chapterRepository.filterUncachedChapters(chapterUrls);

    if (uncachedUrls.isEmpty) {
      LoggerService.instance.i(
        '✅ "$novelTitle" 所有章节已缓存',
        category: LogCategory.cache,
        tags: ['preload', novelUrl],
      );
      return;
    }

    // 用原始索引 + 未缓存 Set 创建任务（避免过滤后索引错位）
    final uncachedSet = uncachedUrls.toSet();
    final tasks = _createTasks(
      novelUrl,
      novelTitle,
      chapterUrls,
      currentIndex,
      uncachedSet,
    );

    // 去重并入队
    int addedCount = 0;
    for (final task in tasks) {
      if (!_enqueuedUrls.contains(task.chapterUrl)) {
        _queue.addLast(task);
        _enqueuedUrls.add(task.chapterUrl);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      LoggerService.instance.i(
        '📚 开始预加载: $novelTitle, 当前第${currentIndex + 1}章, 待缓存$addedCount个',
        category: LogCategory.cache,
        tags: ['preload', novelUrl, 'start'],
      );

      // 启动处理（如果未在运行且未暂停）
      if (!_isPaused) {
        _processQueue();
      }
    } else {
      LoggerService.instance.d(
        '⏭️ 所有任务已在队列中',
        category: LogCategory.cache,
        tags: ['preload', novelUrl],
      );
    }
  }

  /// 创建预加载任务（后续章节优先，前序章节次之）
  ///
  /// 基于 [chapterUrls] 的原始 [currentIndex] 分割前后序，
  /// 通过 [uncachedSet] 跳过已缓存章节，避免索引映射错位。
  List<PreloadTask> _createTasks(
    String novelUrl,
    String novelTitle,
    List<String> chapterUrls,
    int currentIndex,
    Set<String> uncachedSet,
  ) {
    final tasks = <PreloadTask>[];

    if (chapterUrls.isEmpty || uncachedSet.isEmpty) {
      return tasks;
    }

    final safeIndex = currentIndex.clamp(0, chapterUrls.length - 1);

    // 首先添加后续章节（优先级高）
    for (int i = safeIndex + 1; i < chapterUrls.length; i++) {
      if (uncachedSet.contains(chapterUrls[i])) {
        tasks.add(PreloadTask(
          chapterUrl: chapterUrls[i],
          novelUrl: novelUrl,
          novelTitle: novelTitle,
          chapterIndex: i,
        ));
      }
    }

    // 然后添加前序章节（优先级低）
    for (int i = safeIndex - 1; i >= 0; i--) {
      if (uncachedSet.contains(chapterUrls[i])) {
        tasks.add(PreloadTask(
          chapterUrl: chapterUrls[i],
          novelUrl: novelUrl,
          novelTitle: novelTitle,
          chapterIndex: i,
        ));
      }
    }

    return tasks;
  }

  /// 串行处理队列（智能速率限制：缓存章节无等待，爬虫章节30秒间隔）
  ///
  /// 并发安全: 通过 _isRunning 标志确保同一时间只有一个循环执行
  Future<void> _processQueue() async {
    if (_isRunning) return;
    _isRunning = true;

    final startTime = DateTime.now();

    try {
      while (_queue.isNotEmpty && !_shouldStop && !_isPaused) {
        // 从队列头部取出任务
        final task = _queue.removeFirst();
        _enqueuedUrls.remove(task.chapterUrl);
        _currentTask = task;

        try {
          // 获取内容 — 使用 low 优先级
          final result = await _fetchChapterContent(task.chapterUrl);

          // 如果结果是 busy（被抢占），将任务放回队列头部，退出循环等待恢复
          if (result.isBusy) {
            _queue.addFirst(task);
            _enqueuedUrls.add(task.chapterUrl);
            _currentTask = null;
            LoggerService.instance.i(
              'PreloadService: 任务被抢占，放回队列 url=${task.chapterUrl}',
              category: LogCategory.cache,
              tags: ['preload', 'preempted'],
            );
            break; // 退出循环，等待 resume
          }

          if (result.isNoScript) {
            // 无脚本，跳过此任务
            _totalFailed++;
            _addFailedHistory(task, 'noScript');
            LoggerService.instance.d(
              '预加载 noScript: url=${task.chapterUrl} domain=${Uri.tryParse(task.chapterUrl)?.host}',
              category: LogCategory.cache,
              tags: ['preload', 'no_script'],
            );
            _currentTask = null;
            await _rateLimiter.acquire();
            continue;
          }

          if (result.isLoadFailed || result.isScriptError) {
            // 页面加载失败 / 脚本缺陷：跳过此任务
            final reason = result.isScriptError ? 'scriptError' : 'loadFailed';
            _totalFailed++;
            _addFailedHistory(task, reason);
            LoggerService.instance.w(
              '预加载 $reason: url=${task.chapterUrl} domain=${Uri.tryParse(task.chapterUrl)?.host}',
              category: LogCategory.cache,
              tags: ['preload', reason],
            );
            _currentTask = null;
            await _rateLimiter.acquire();
            continue;
          }

          // 成功：保存到数据库
          final chapter = Chapter(
            url: task.chapterUrl,
            title: '',
            content: result.content.content,
          );
          await _chapterRepository.cacheChapter(
              task.novelUrl, chapter, result.content.content);

          _totalProcessed++;
          _addProcessedHistory(task);

          // 每处理5个汇总一次进度
          if (_totalProcessed % 5 == 0) {
            LoggerService.instance.d(
              '预加载进度: $_totalProcessed个已处理, $_totalFailed个失败, 剩余${_queue.length}个',
              category: LogCategory.cache,
              tags: ['preload', 'progress'],
            );
          }

          // 通知章节缓存完成（供章节列表页面更新UI）
          _progressController.add(PreloadProgressUpdate(
            novelUrl: task.novelUrl,
            chapterUrl: task.chapterUrl,
            novelTitle: task.novelTitle,
            chapterIndex: task.chapterIndex,
          ));

          _currentTask = null;

          // 根据来源控制速率
          if (result.content.fromCache) {
            // 缓存命中：重置速率限制器，下一条可以立即获取
            _rateLimiter.reset();
          } else {
            // 爬虫抓取：等待30秒间隔后再获取下一条
            await _rateLimiter.acquire();
          }
        } catch (e, st) {
          _totalFailed++;
          _addFailedHistory(task, e.toString());
          LoggerService.instance.e(
            '预加载单任务失败: url=${task.chapterUrl} - $e',
            stackTrace: st.toString(),
            category: LogCategory.cache,
            tags: ['preload', 'task_failed'],
          );
          _currentTask = null;
          // 失败时也等待间隔
          await _rateLimiter.acquire();
        }
      }

      final duration = DateTime.now().difference(startTime);

      if (_isPaused) {
        LoggerService.instance.i(
          '⏸️ 预加载已暂停: 剩余${_queue.length}个任务',
          category: LogCategory.cache,
          tags: ['preload', 'paused'],
        );
      } else {
        LoggerService.instance.i(
          '✅ 预加载完成: 成功$_totalProcessed个, 失败$_totalFailed个, 耗时${duration.inSeconds}s',
          category: LogCategory.cache,
          tags: ['preload', 'complete'],
        );
      }
    } catch (e) {
      LoggerService.instance.e(
        '❌ 队列处理异常: $e',
        category: LogCategory.cache,
        tags: ['preload', 'error'],
      );
    } finally {
      _isRunning = false; // ✅ 释放锁
    }
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'queue_length': _queue.length,
      'is_processing': isProcessing,
      'is_paused': _isPaused,
      'last_active_novel': _lastActiveNovel,
      'novel_states': _novelCurrentIndex,
      'total_processed': _totalProcessed,
      'total_failed': _totalFailed,
      'enqueued_urls': _queue.length,
    };
  }

  /// 获取队列快照（按 FIFO 顺序，最先处理的在最前）
  List<PreloadTask> getQueueSnapshot() =>
      List<PreloadTask>.unmodifiable(_queue);

  /// 获取已入队去重快照（与队列快照一致；保留 API 兼容）
  List<PreloadTask> getEnqueuedSnapshot() =>
      List<PreloadTask>.unmodifiable(_queue);

  /// 获取已处理（成功）历史快照，最新在前
  List<PreloadHistoryEntry> getProcessedHistory() =>
      List.unmodifiable(_processedHistory);

  /// 获取已失败历史快照，最新在前
  List<PreloadHistoryEntry> getFailedHistory() =>
      List.unmodifiable(_failedHistory);

  /// 添加成功历史（最新在前，超限移除末尾）
  void _addProcessedHistory(PreloadTask task) {
    _processedHistory.insert(
      0,
      PreloadHistoryEntry(
        novelTitle: task.novelTitle,
        chapterIndex: task.chapterIndex,
        chapterUrl: task.chapterUrl,
        novelUrl: task.novelUrl,
        time: DateTime.now(),
      ),
    );
    if (_processedHistory.length > _historyLimit) {
      _processedHistory.removeLast();
    }
  }

  /// 添加失败历史（最新在前，超限移除末尾）
  void _addFailedHistory(PreloadTask task, String error) {
    _failedHistory.insert(
      0,
      PreloadHistoryEntry(
        novelTitle: task.novelTitle,
        chapterIndex: task.chapterIndex,
        chapterUrl: task.chapterUrl,
        novelUrl: task.novelUrl,
        time: DateTime.now(),
        error: error,
      ),
    );
    if (_failedHistory.length > _historyLimit) {
      _failedHistory.removeLast();
    }
  }

  /// 清空队列（用于测试或强制重置）
  Future<void> clearQueue() async {
    // 设置停止标志，让正在运行的循环在下一次条件检查时退出
    _shouldStop = true;
    _queue.clear();
    _enqueuedUrls.clear();

    // 等待正在运行的循环退出（队列已空 + _shouldStop，会很快结束）
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (_isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_isRunning) {
      LoggerService.instance.w(
        'clearQueue: 等待处理退出超时（2s），强制重置 _isRunning',
        category: LogCategory.cache,
        tags: ['preload', 'force_reset'],
      );
      _isRunning = false;
    }

    // 清理其余状态
    _novelCurrentIndex.clear();
    _lastActiveNovel = null;
    _rateLimiter.reset();
    _totalProcessed = 0;
    _totalFailed = 0;
    _processedHistory.clear();
    _failedHistory.clear();
    _currentTask = null;

    // 重置停止和暂停标志
    _shouldStop = false;
    _isPaused = false;

    LoggerService.instance.i(
      '预加载队列已清空',
      category: LogCategory.cache,
      tags: ['preload', 'clear'],
    );
  }

  /// 暂停预加载处理
  ///
  /// 当阅读器需要使用 WebView 时调用。即使当前没有任务正在处理，
  /// 也会设置暂停标志，避免 [enqueueTasks] 内部启动新的处理循环。
  /// 队列处理在 [resume] 被调用之前不会启动。
  void pause() {
    if (!_isPaused) {
      _isPaused = true;
      LoggerService.instance.i(
        'PreloadService: 预加载已暂停（阅读器请求优先）',
        category: LogCategory.cache,
        tags: ['preload', 'pause'],
      );
    }
  }

  /// 恢复预加载处理
  ///
  /// 阅读器加载章节完成后调用，重新启动队列处理。
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      LoggerService.instance.i(
        'PreloadService: 预加载已恢复',
        category: LogCategory.cache,
        tags: ['preload', 'resume'],
      );
      // 重新启动队列处理
      _processQueue();
    }
  }

  /// 是否已暂停
  bool get isPaused => _isPaused;

  /// 获取队列长度
  int get queueLength => _queue.length;

  /// 是否正在处理队列
  bool get isProcessing => _isRunning;

  /// 释放资源
  void dispose() {
    _progressController.close();
    _rateLimiter.reset();
    clearQueue();
  }

  /// 获取章节内容（纯 Headless WebView，不再回退后端 API）
  Future<FetchContentResult> _fetchChapterContent(String chapterUrl) async {
    // Headless WebView（如有该域名的提取脚本）
    if (_headlessService != null) {
      final result = await _headlessService!.fetchContent(
        chapterUrl,
        priority: FetchPriority.low,
      );
      if (result.isSuccess) {
        LoggerService.instance.d(
          '预加载: Headless WebView 获取成功',
          category: LogCategory.cache,
          tags: ['preload', 'headless-webview'],
        );
        return result;
      }
      // busy 或 noScript 传递给调用方
      return result;
    }

    // 无 headless 服务
    LoggerService.instance.w(
      '预加载: 无提取脚本或 headless 获取失败: $chapterUrl',
      category: LogCategory.cache,
      tags: ['preload', 'headless-webview', 'no-script'],
    );
    return FetchContentResult.noScript();
  }
}
