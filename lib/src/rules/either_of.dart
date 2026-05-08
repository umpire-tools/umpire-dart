import 'rule.dart';
import '../composite.dart';

/// Passes if ANY branch passes, where each branch ANDs its rules together.
///
/// ```dart
/// eitherOf('auth', {
///   'password': [enabledWhen('submit', predicate: hasEmail), enabledWhen('submit', predicate: hasPassword)],
///   'sso': [enabledWhen('submit', predicate: ssoAvailable)],
/// })
/// ```
Rule eitherOf(String groupName, Map<String, List<Rule>> branches, {String? reason}) {
  final branchNames = branches.keys.toList();

  if (branchNames.isEmpty) {
    throw ArgumentError('eitherOf("$groupName") must include at least one branch');
  }

  for (final entry in branches.entries) {
    if (entry.value.isEmpty) {
      throw ArgumentError(
        'eitherOf("$groupName") branch "${entry.key}" must not be empty',
      );
    }
  }

  // Validate all rules target the same fields
  final allRules = branchNames.expand((b) => branches[b]!).toList();
  final expectedTargets = {...allRules.first.targets};
  final expectedConstraint = _getConstraint(allRules.first);
  final allSources = <String>{};

  for (final rule in allRules) {
    final ruleTargets = {...rule.targets};
    if (ruleTargets.length != expectedTargets.length ||
        !ruleTargets.containsAll(expectedTargets)) {
      throw ArgumentError(
        'eitherOf("$groupName") rules must target the same fields',
      );
    }
    if (_getConstraint(rule) != expectedConstraint) {
      throw ArgumentError(
        'eitherOf("$groupName") cannot mix fairWhen rules with availability rules',
      );
    }
    allSources.addAll(rule.sources);
  }

  return Rule(
    type: 'eitherOf',
    targets: expectedTargets.toList(),
    sources: allSources.toList(),
    constraint: expectedConstraint,
    evaluate: (values, conditions, [prev, fields, availability]) {
      // Evaluate each branch's rules
      final branchEvaluations = <String, List<Map<String, RuleEvaluation>>>{};
      for (final branchName in branchNames) {
        branchEvaluations[branchName] = branches[branchName]!
            .map((r) => r.evaluate(values, conditions, prev, fields, availability))
            .toList();
      }

      return Map.fromEntries(expectedTargets.map((target) {
        // AND each branch's rule results for this target, then OR branches
        final branchResults = branchNames.map((branchName) {
          final targetResults = branchEvaluations[branchName]!
              .map((e) => e[target] ?? const RuleEvaluation(enabled: true, reason: null))
              .toList();
          return combineCompositeResults(expectedConstraint, 'and', targetResults);
        }).toList();

        final combined = combineCompositeResults(expectedConstraint, 'or', branchResults);
        return MapEntry(target, combined);
      }));
    },
  );
}

String _getConstraint(Rule rule) {
  if (rule.constraint == 'fair') return 'fair';
  return 'enabled';
}
