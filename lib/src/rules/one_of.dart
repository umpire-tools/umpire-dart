import 'rule.dart';
import '../satisfaction.dart';

/// Only one branch of fields can be enabled at a time.
///
/// The active branch is detected automatically (first branch with a satisfied
/// field). Pass [activeBranch] to override detection.
Rule oneOf(
  String group,
  Map<String, List<String>> branches, {
  String? activeBranch,
  String? reason,
}) {
  final branchNames = branches.keys.toList();
  final targets = branchNames.expand((b) => branches[b]!).toList();

  if (branchNames.isEmpty) {
    throw ArgumentError('oneOf("$group") must include at least one branch');
  }

  for (final entry in branches.entries) {
    if (entry.value.isEmpty) {
      throw ArgumentError(
        'oneOf("$group") branch "${entry.key}" must not be empty',
      );
    }
  }

  // Validate no field appears in multiple branches
  final seen = <String>{};
  for (final fields in branches.values) {
    for (final f in fields) {
      if (seen.contains(f)) {
        throw ArgumentError(
          'oneOf("$group") field "$f" appears in multiple branches',
        );
      }
      seen.add(f);
    }
  }

  if (activeBranch != null && !branches.containsKey(activeBranch)) {
    throw ArgumentError(
      'Unknown active branch "$activeBranch" for oneOf("$group")',
    );
  }

  String? _detectActiveBranch(
    Map<String, dynamic> values,
    Map<String, dynamic>? fields,
  ) {
    if (activeBranch != null) return activeBranch;

    final satisfiedBranches = branchNames.where((name) {
      return branches[name]!.any((f) => isSatisfied(values[f], null));
    }).toList();

    if (satisfiedBranches.isEmpty) return null;
    return satisfiedBranches.first;
  }

  return Rule(
    type: 'oneOf',
    targets: targets,
    sources: targets,
    evaluate: (values, conditions, [prev, fields, availability]) {
      final detected = _detectActiveBranch(values, fields);

      if (detected == null) {
        return Map.fromEntries(
          targets.map((t) =>
              MapEntry(t, const RuleEvaluation(enabled: true, reason: null))),
        );
      }

      return Map.fromEntries(targets.map((target) {
        final inActiveBranch = branches[detected]!.contains(target);
        return MapEntry(
          target,
          RuleEvaluation(
            enabled: inActiveBranch,
            reason: inActiveBranch
                ? null
                : reason ?? 'conflicts with $detected strategy',
          ),
        );
      }));
    },
  );
}
