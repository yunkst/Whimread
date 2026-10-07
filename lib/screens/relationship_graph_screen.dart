import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_force_directed_graph/flutter_force_directed_graph.dart';

import '../../core/providers/database_providers.dart';
import '../../core/providers/relationship_graph_providers.dart';
import '../../models/character_relationship.dart';
import '../../models/relation_type.dart';
import '../../models/relationship_graph_snapshot.dart';
import '../widgets/relationship/timeline_chapter_slider.dart';
import '../widgets/relationship/relationship_graph_view.dart';

/// 人物关系图页面。
///
/// 顶部章节时间轴滑块 + 下方力导向图。拖动滑块按章节过滤"已登场人物 +
/// 当前生效关系",复现人物关系随剧情的演变。
class RelationshipGraphScreen extends ConsumerStatefulWidget {
  final String novelUrl;

  const RelationshipGraphScreen({super.key, required this.novelUrl});

  @override
  ConsumerState<RelationshipGraphScreen> createState() =>
      _RelationshipGraphScreenState();
}

class _RelationshipGraphScreenState
    extends ConsumerState<RelationshipGraphScreen> {
  /// 滑块手动覆盖值(为 null 表示跟随阅读进度)。
  int? _chapterOverride;

  /// 章节总数(用于滑块 max),异步加载。
  int? _totalChapters;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadTotalChapters();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTotalChapters() async {
    final repo = ref.read(chapterRepositoryProvider);
    final count = await repo.getTotalChaptersCount(widget.novelUrl);
    if (mounted) setState(() => _totalChapters = count);
  }

  void _onSliderChanged(int v) {
    // debounce ~150ms,避免拖动时频繁重查。
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _chapterOverride = v);
    });
    // 立即响应,让滑块手感跟手(debounce 仅限重查询,setState 立即)
    setState(() => _chapterOverride = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultChapterAsync = ref.watch(currentChapterProvider(widget.novelUrl));

    return Scaffold(
      appBar: AppBar(title: const Text('人物关系图')),
      body: defaultChapterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载阅读进度失败: $e')),
        data: (defaultChapter) {
          final maxChapter = (_totalChapters ?? 1) - 1;
          final chapter =
              (_chapterOverride ?? defaultChapter).clamp(0, maxChapter < 0 ? 0 : maxChapter);
          final snapAsync =
              ref.watch(relationshipGraphProvider(widget.novelUrl, chapter));

          return Column(
            children: [
              TimelineChapterSlider(
                maxChapter: maxChapter < 0 ? 0 : maxChapter,
                chapter: chapter,
                onChanged: _onSliderChanged,
              ),
              if (_chapterOverride != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _chapterOverride = null),
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('回到当前进度'),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: snapAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载关系图失败: $e')),
                  data: (snap) => snap.isEmpty
                      ? Center(
                          child: Text(
                            '本章暂无已登场人物',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : _GraphView(snapshot: snap),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── 力导向图节点数据 ───────────────────────────────────────────
/// 力导向图视图:把 [RelationshipGraphSnapshot] 渲染为节点 + 边。
class _GraphView extends ConsumerStatefulWidget {
  final RelationshipGraphSnapshot snapshot;
  const _GraphView({required this.snapshot});

  @override
  ConsumerState<_GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends ConsumerState<_GraphView> {
  late ForceDirectedGraphController<GraphNode> _controller;

  @override
  void initState() {
    super.initState();
    _controller = ForceDirectedGraphController<GraphNode>();
    _buildGraph(widget.snapshot);
  }

  @override
  void didUpdateWidget(covariant _GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _buildGraph(widget.snapshot);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _buildGraph(RelationshipGraphSnapshot snap) {
    final newGraph = ForceDirectedGraph<GraphNode>();

    final nodeMap = <int, Node<GraphNode>>{};
    for (final c in snap.characters) {
      final id = c.id;
      if (id == null) continue;
      final node = GraphNode(id, c.name);
      final n = Node<GraphNode>(node);
      newGraph.addNode(n);
      nodeMap[id] = n;
    }

    for (final rel in snap.relationships) {
      final a = nodeMap[rel.sourceCharacterId];
      final b = nodeMap[rel.targetCharacterId];
      if (a == null || b == null) continue;
      final edge = Edge(a, b);
      if (!newGraph.edges.contains(edge)) {
        newGraph.addEdge(edge);
      }
    }

    // controller.graph 的 setter 会清空旧图、写入新图、并 notifyListeners。
    _controller.graph = newGraph;
  }

  /// 关系类型 → 在 [snap] 里查到 source/target 与 strength 的映射,用于边上色/线宽。
  Map<String, CharacterRelationship> _buildEdgeLabelMap(
      RelationshipGraphSnapshot snap) {
    // key = "minId-maxId"
    final m = <String, CharacterRelationship>{};
    for (final rel in snap.relationships) {
      final lo = rel.sourceCharacterId < rel.targetCharacterId
          ? rel.sourceCharacterId
          : rel.targetCharacterId;
      final hi = rel.sourceCharacterId < rel.targetCharacterId
          ? rel.targetCharacterId
          : rel.sourceCharacterId;
      m['$lo-$hi'] = rel;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelMap = _buildEdgeLabelMap(widget.snapshot);

    return ForceDirectedGraphWidget<GraphNode>(
      controller: _controller,
      nodesBuilder: (context, data) => GraphNodeWidget(
        data: data,
        color: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
      ),
      edgesBuilder: (context, a, b, distance) {
        // _GraphView build 在 controller.sync 后,边已建好;label 由两端 id 查。
        // 这里 a/b 是 GraphNode,通过 _buildEdgeLabelMap 查关系类型。
        final lo = a.id < b.id ? a.id : b.id;
        final hi = a.id < b.id ? b.id : a.id;
        final rel = labelMap['$lo-$hi'];
        final color = rel?.relationType.color ?? theme.colorScheme.outline;
        final symmetric = rel?.relationType.symmetric ?? true;
        final strength = rel?.strength ?? 3;
        final label = rel != null
            ? RelationType.values
                .byName(rel.relationType.name)
                .labelFor(isSource: rel.sourceCharacterId == a.id)
            : '';
        return GraphEdgeWidget(
          color: color,
          strokeWidth: 1.0 + strength * 0.7,
          dashed: !symmetric,
          label: label,
        );
      },
    );
  }
}
