import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_force_directed_graph/flutter_force_directed_graph.dart';

import '../../models/character_relationship.dart';
import '../../models/relationship_graph_snapshot.dart';

/// 关系图视图(可复用 widget)。
///
/// 维护 [_nodeCache] 跨 snapshot 复用 Node,保证同一 characterId 在不同
/// 章节下位置稳定(切章节不抖)。已消失的角色从 graph 移除但保留在 cache,
/// 再次出现时复用原 position。
class RelationshipGraphView extends ConsumerStatefulWidget {
  final RelationshipGraphSnapshot snapshot;

  const RelationshipGraphView({super.key, required this.snapshot});

  @override
  ConsumerState<RelationshipGraphView> createState() => GraphViewState();
}

class GraphViewState extends ConsumerState<RelationshipGraphView> {
  /// 力导向控制器。private;测试通过 [debugNodes] 观察节点位置
  /// (见 test/widget/relationship_graph_node_cache_test.dart)。
  late final ForceDirectedGraphController<GraphNode> _controller =
      ForceDirectedGraphController<GraphNode>();

  /// 跨 snapshot 保留 Node,避免切章节时人物位置重新随机。
  final Map<int, Node<GraphNode>> _nodeCache = {};

  /// 边标签映射(在 [_applySnapshot] 末尾与节点/边同步构建,避免 build 每帧重算)。
  Map<(int, int), CharacterRelationship> _edgeLabelMap = const {};

  @override
  void initState() {
    super.initState();
    _applySnapshot(widget.snapshot);
  }

  @override
  void didUpdateWidget(covariant RelationshipGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _applySnapshot(widget.snapshot);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 增量同步:复用 _nodeCache 里的 Node,只增/删变化的人物;边按当前
  /// snapshot 完整重建(Node 不重建,所以位置稳定)。
  void _applySnapshot(RelationshipGraphSnapshot snap) {
    final graph = _controller.graph;

    // 1) 新登场/再登场人物:从 cache 取或新建 Node,确保在 graph 里。
    //    (cache 里的 Node 可能因"消失-再出现"被 graph.deleteNode 移除过,
    //    所以即使 cache 命中也要检查 graph,必要时重新 add。)
    final presentIds = <int>{};
    for (final c in snap.characters) {
      final id = c.id;
      if (id == null) continue;
      presentIds.add(id);
      var node = _nodeCache[id];
      if (node == null) {
        node = Node<GraphNode>(GraphNode(id, c.name));
        _nodeCache[id] = node;
        graph.addNode(node);
      } else if (!graph.nodes.contains(node)) {
        graph.addNode(node);
      }
    }

    // 2) 已消失人物:从 graph 移除(边自动脱落),但**保留 cache**。
    final staleIds = _nodeCache.keys
        .where((id) => !presentIds.contains(id))
        .toList();
    for (final id in staleIds) {
      graph.deleteNode(_nodeCache[id]!);
    }

    // 3) 边:按当前 snapshot 完整重建;同时构建 labelMap 供 build 的 edgesBuilder 查询。
    graph.edges.clear();
    final labelMap = <(int, int), CharacterRelationship>{};
    for (final rel in snap.relationships) {
      final a = _nodeCache[rel.sourceCharacterId];
      final b = _nodeCache[rel.targetCharacterId];
      if (a == null || b == null) continue;
      final edge = Edge(a, b);
      if (!graph.edges.contains(edge)) {
        graph.addEdge(edge);
      }
      final lo = rel.sourceCharacterId < rel.targetCharacterId
          ? rel.sourceCharacterId
          : rel.targetCharacterId;
      final hi = rel.sourceCharacterId < rel.targetCharacterId
          ? rel.targetCharacterId
          : rel.sourceCharacterId;
      labelMap[(lo, hi)] = rel;
    }
    _edgeLabelMap = labelMap;

    // 4) 通知 widget 重绘(并启动包内的 ticker 推进布局)。
    _controller.needUpdate();
  }

  /// 测试/调试用:返回当前 graph 里的 Node 列表。
  List<Node<GraphNode>> debugNodes() => _controller.graph.nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelMap = _edgeLabelMap;

    return ForceDirectedGraphWidget<GraphNode>(
      controller: _controller,
      nodesBuilder: (context, data) => _NodeWidget(
        data: data,
        color: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
      ),
      edgesBuilder: (context, a, b, distance) {
        final lo = a.id < b.id ? a.id : b.id;
        final hi = a.id < b.id ? b.id : a.id;
        final rel = labelMap[(lo, hi)];
        final color = rel?.relationType.color ?? theme.colorScheme.outline;
        final symmetric = rel?.relationType.symmetric ?? true;
        final strength = rel?.strength ?? 3;
        final label = rel != null
            ? rel.relationType.labelFor(isSource: rel.sourceCharacterId == a.id)
            : '';
        return _EdgeWidget(
          color: color,
          strokeWidth: 1.0 + strength * 0.7,
          dashed: !symmetric,
          label: label,
        );
      },
    );
  }
}

// ─── 力导向图节点数据 ───────────────────────────────────────────
class GraphNode {
  final int id;
  final String name;
  const GraphNode(this.id, this.name);

  @override
  bool operator ==(Object other) => other is GraphNode && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => name;
}

class _NodeWidget extends StatelessWidget {
  final GraphNode data;
  final Color color;
  final Color foreground;
  const _NodeWidget({
    required this.data,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        data.name,
        style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _EdgeWidget extends StatelessWidget {
  final Color color;
  final double strokeWidth;
  final bool dashed;
  final String label;
  const _EdgeWidget({
    required this.color,
    required this.strokeWidth,
    required this.dashed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
