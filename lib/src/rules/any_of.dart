import 'rule.dart';
import '../composite.dart';

/// Passes if ANY of the inner rules pass (OR logic).
Rule anyOf(List<Rule> rules) {
  if (rules.isEmpty) {
    throw ArgumentError('anyOf() requires at least one rule');
  }

  // All rules must target the same fields
  final expectedTargets = {...rules.first.targets};
  final expectedConstraint = _ruleConstraint(rules.first);
  final allSources = <String>{};

  for (final rule in rules) {
    final ruleTargets = {...rule.targets};
    if (ruleTargets.length != expectedTargets.length ||
        !ruleTargets.containsAll(expectedTargets)) {
      throw ArgumentError('anyOf() rules must target the same fields');
    }
    if (_ruleConstraint(rule) != expectedConstraint) {
      throw ArgumentError(
          'anyOf() cannot mix fairWhen rules with availability rules');
    }
    allSources.addAll(rule.sources);
  }

  return Rule(
    type: 'anyOf',
    targets: expectedTargets.toList(),
    sources: allSources.toList(),
    evaluate: (values, conditions, [prev, fields, availability]) {
      final evaluations = rules
          .map((r) => r.evaluate(values, conditions, prev, fields, availability))
          .toList();

      return Map.fromEntries(expectedTargets.map((target) {
        final targetResults = evaluations.map((e) {
          return e[target] ??
              const RuleEvaluation(enabled: true, reason: null);
        }).toList();

        final combined = combineCompositeResults(
          expectedConstraint == 'fair' ? 'fair' : 'enabled',
          'or',
          targetResults,
        );

        return MapEntry(target, combined);
      }));
    },
  );
}

String _ruleConstraint(Rule rule) {
  if (rule.type == 'fairWhen') return 'fair';
  return 'enabled';
}
