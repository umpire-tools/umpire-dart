import 'field_def.dart';
import 'rules/rule.dart';

class DependencyGraph {
  final List<String> nodes;
  final Map<String, List<String>> adjacency;
  final Map<String, int> incomingCounts;

  DependencyGraph({
    required this.nodes,
    required this.adjacency,
    required this.incomingCounts,
  });
}

/// Builds a dependency graph from field definitions and rules.
DependencyGraph buildGraph(Map<String, FieldDef> fields, List<Rule> rules) {
  final nodes = fields.keys.toList();
  final adjacency = <String, List<String>>{};
  final incomingCounts = <String, int>{};
  final seenEdges = <String>{};

  for (final node in nodes) {
    adjacency[node] = [];
    incomingCounts[node] = 0;
  }

  void addEdge(String from, String to, String type, bool ordering) {
    final edgeKey = '$from:$to:$type:$ordering';
    if (seenEdges.contains(edgeKey)) return;
    seenEdges.add(edgeKey);

    if (!ordering) return;

    adjacency.putIfAbsent(from, () => []).add(to);
    incomingCounts.putIfAbsent(from, () => 0);
    incomingCounts[to] = (incomingCounts[to] ?? 0) + 1;
  }

  for (final rule in rules) {
    final sources = _getOrderingSources(rule);
    for (final source in sources) {
      for (final target in rule.targets) {
        if (source == target) continue;
        addEdge(source, target, rule.type, true);
      }
    }
  }

  return DependencyGraph(
    nodes: nodes,
    adjacency: adjacency,
    incomingCounts: incomingCounts,
  );
}

/// Returns ordering source fields for a rule.
///
/// oneOf rules are excluded from ordering — branch resolution is handled
/// internally within the rule evaluation and does not create inter-field
/// dependencies that require topological ordering.
List<String> _getOrderingSources(Rule rule) {
  switch (rule.type) {
    case 'enabledWhen':
    case 'fairWhen':
    case 'oneOf':
      return [];
    default:
      return rule.sources;
  }
}

/// Detects cycles in the graph and throws if found.
void detectCycles(DependencyGraph graph) {
  final visited = <String>{};
  final active = <String>{};
  final path = <String>[];

  List<String>? visit(String node) {
    visited.add(node);
    active.add(node);
    path.add(node);

    for (final next in graph.adjacency[node] ?? <String>[]) {
      if (!visited.contains(next)) {
        final cycle = visit(next);
        if (cycle != null) return cycle;
        continue;
      }

      if (!active.contains(next)) continue;

      final cycleStart = path.indexOf(next);
      return [...path.sublist(cycleStart), next];
    }

    path.removeLast();
    active.remove(node);
    return null;
  }

  for (final node in graph.nodes) {
    if (visited.contains(node)) continue;

    final cycle = visit(node);
    if (cycle != null) {
      throw StateError('Cycle detected: ${cycle.join(' → ')}');
    }
  }
}

/// Produces a topological ordering of fields.
List<String> topologicalSort(
  DependencyGraph graph,
  List<String> fieldNames,
) {
  final orderedFields = Set<String>.from(fieldNames).toList();
  final incomingCounts = <String, int>{};

  for (final field in orderedFields) {
    incomingCounts[field] = graph.incomingCounts[field] ?? 0;
  }

  final queue = orderedFields
      .where((f) => (incomingCounts[f] ?? 0) == 0)
      .toList();
  final result = <String>[];

  for (var index = 0; index < queue.length; index++) {
    final node = queue[index];
    result.add(node);

    for (final next in graph.adjacency[node] ?? <String>[]) {
      final remaining = (incomingCounts[next] ?? 0) - 1;
      incomingCounts[next] = remaining;
      if (remaining == 0) {
        queue.add(next);
      }
    }
  }

  if (result.length != orderedFields.length) {
    throw StateError('Unable to produce topological order — possible cycle');
  }

  return result;
}
