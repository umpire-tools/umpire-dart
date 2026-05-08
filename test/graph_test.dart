import 'package:test/test.dart';
import 'package:umpire/umpire.dart';
import 'package:umpire/src/graph.dart';

void main() {
  group('buildGraph', () {
    test('simple dependency chain (a → b → c)', () {
      final fields = {
        'a': FieldDef(),
        'b': FieldDef(),
        'c': FieldDef(),
      };
      final rules = [
        requires('b', dependency: 'a'),
        requires('c', dependency: 'b'),
      ];
      final graph = buildGraph(fields, rules);

      expect(graph.adjacency['a']!.contains('b'), isTrue);
      expect(graph.adjacency['b']!.contains('c'), isTrue);
    });

    test('no-cycle graph produces correct topological order', () {
      final fields = {
        'a': FieldDef(),
        'b': FieldDef(),
        'c': FieldDef(),
      };
      final rules = [
        requires('b', dependency: 'a'),
        requires('c', dependency: 'b'),
      ];
      final graph = buildGraph(fields, rules);
      detectCycles(graph);
      final order = topologicalSort(graph, fields.keys.toList());

      final aPos = order.indexOf('a');
      final bPos = order.indexOf('b');
      final cPos = order.indexOf('c');
      expect(aPos < bPos, isTrue);
      expect(bPos < cPos, isTrue);
    });
  });

  group('detectCycles', () {
    test('cycle detection throws on circular dependency', () {
      final fields = {
        'a': FieldDef(),
        'b': FieldDef(),
      };
      final rules = [
        requires('a', dependency: 'b'),
        requires('b', dependency: 'a'),
      ];
      final graph = buildGraph(fields, rules);

      expect(
        () => detectCycles(graph),
        throwsStateError,
      );
    });

    test('self-edges are skipped (no cycles from self-references)', () {
      // Self-referencing edge should be skipped by buildGraph
      final fields = {
        'a': FieldDef(),
        'b': FieldDef(),
      };
      final rules = [
        requires('b', dependency: 'a'),
        requires('a', dependency: 'a'), // self-edge
      ];
      final graph = buildGraph(fields, rules);
      // Self-edge from 'a' to 'a' should be skipped
      expect(graph.adjacency['a']!.contains('a'), isFalse);
      // Normal edge should still exist
      expect(graph.adjacency['a']!.contains('b'), isTrue);
      detectCycles(graph); // should not throw
    });
  });
}
