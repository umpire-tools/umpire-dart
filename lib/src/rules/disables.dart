import 'rule.dart';
import '../satisfaction.dart';

/// Disables [targets] whenever [source] is satisfied, or whenever [when]
/// predicate returns true.
///
/// At least one of [source] or [when] must be provided.
Rule disables(
  String? source,
  List<String> targets, {
  Predicate? when,
  String? reason,
}) {
  if (source == null && when == null) {
    throw ArgumentError('disables requires either a source field or a when predicate');
  }

  final sourceLabel = source ?? 'condition';
  final sources = source != null ? [source] : <String>[];

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
    sources: sources,
    evaluate: (values, conditions, [prev, fields, availability]) {
      final active = isSourceActive(values, conditions, fields);
      final defaultReason = 'overridden by $sourceLabel';
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
