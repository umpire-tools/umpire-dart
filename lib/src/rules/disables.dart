import 'rule.dart';
import '../satisfaction.dart';

/// Disables [targets] whenever [source] is satisfied.
Rule disables(
  String source,
  List<String> targets, {
  Predicate? when,
  String? reason,
}) {
  bool isSourceActive(
    Map<String, dynamic> values,
    Map<String, dynamic> conditions,
    Map<String, dynamic>? fields,
  ) {
    if (when != null) return when(values, conditions);
    return isSatisfied(values[source], null);
  }

  return Rule(
    type: 'disables',
    targets: targets,
    sources: [source],
    evaluate: (values, conditions, [prev, fields, availability]) {
      final active = isSourceActive(values, conditions, fields);
      final defaultReason = 'overridden by $source';
      final resolvedReason = active ? reason ?? defaultReason : null;

      return Map.fromEntries(targets.map((t) => MapEntry(
            t,
            RuleEvaluation(
              enabled: !active,
              reason: resolvedReason,
            ),
          )));
    },
  );
}
