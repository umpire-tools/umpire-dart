import '../field_def.dart';
import '../satisfaction.dart';
import 'rule.dart';

/// Only one branch of fields can be enabled at a time.
///
/// The active branch is detected automatically as the only branch holding a
/// satisfied field. When several branches are satisfied at once, the prior
/// snapshot [prev] decides: a branch that became satisfied since [prev] wins.
/// Without that signal the first satisfied branch is used.
///
/// Pass [activeBranch] to override detection.
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

  bool branchSatisfied(
    String name,
    Map<String, dynamic>? values,
    Map<String, FieldDef>? fieldDefs,
  ) {
    if (values == null) return false;
    return branches[name]!.any(
      (field) => isSatisfied(values[field], fieldDefs?[field]),
    );
  }

  String? detectActiveBranch(
    Map<String, dynamic> values,
    Map<String, dynamic>? prev,
    Map<String, FieldDef>? fieldDefs,
  ) {
    if (activeBranch != null) return activeBranch;

    final satisfiedBranches = branchNames
        .where((name) => branchSatisfied(name, values, fieldDefs))
        .toList();

    if (satisfiedBranches.isEmpty) return null;
    if (satisfiedBranches.length == 1) return satisfiedBranches.first;

    if (prev != null) {
      final newlySatisfiedBranches = satisfiedBranches
          .where((name) => !branchSatisfied(name, prev, fieldDefs))
          .toList();
      if (newlySatisfiedBranches.length == 1) {
        return newlySatisfiedBranches.first;
      }
    }

    return satisfiedBranches.first;
  }

  return Rule(
    type: 'oneOf',
    targets: targets,
    sources: targets,
    evaluate: (values, conditions, [prev, fields, availability]) {
      final detected = detectActiveBranch(values, prev, fields);

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
