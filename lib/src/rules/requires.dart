import 'rule.dart';
import '../satisfaction.dart';

String _resolveReason(
  String? reason,
  Map<String, dynamic> values,
  Map<String, dynamic> conditions,
  String fallback,
) {
  return reason ?? fallback;
}

/// The target field is required only when a predicate or dependency is met.
Rule requires(
  String field, {
  String? dependency,
  Predicate? when,
  String? reason,
}) {
  if (dependency == null && when == null) {
    throw ArgumentError('requires("$field") needs at least a dependency or when');
  }

  final sources = <String>[];
  if (dependency != null) sources.add(dependency);

  return Rule(
    type: 'requires',
    targets: [field],
    sources: sources,
    evaluate: (values, conditions, [prev, fields, availability]) {
      bool passed;

      if (dependency != null) {
        final depVal = values[dependency];
        final depSatisfied = isSatisfied(depVal, fields?[dependency]);
        final depAvailability = availability?[dependency];
        final depEnabled = depAvailability?.enabled ?? true;
        final depFair = depAvailability?.fair ?? true;
        passed = depSatisfied && depEnabled && depFair;
      } else {
        passed = when!(values, conditions);
      }

      if (passed) {
        return {field: const RuleEvaluation(enabled: true, reason: null)};
      }

      final resolvedReason = _resolveReason(
        reason,
        values,
        conditions,
        dependency != null ? 'requires $dependency' : 'required condition not met',
      );

      return {
        field: RuleEvaluation(
          enabled: false,
          reason: resolvedReason,
          reasons: [resolvedReason],
        ),
      };
    },
  );
}

/// Enables [field] only when [predicate] is true.
Rule enabledWhen(
  String field, {
  required Predicate predicate,
  String? reason,
}) {
  return Rule(
    type: 'enabledWhen',
    targets: [field],
    evaluate: (values, conditions, [prev, fields, availability]) {
      final passed = predicate(values, conditions);

      return {
        field: RuleEvaluation(
          enabled: passed,
          reason: passed
              ? null
              : _resolveReason(reason, values, conditions, 'condition not met'),
        ),
      };
    },
  );
}

/// Marks [field] unfair if [predicate] returns false.
Rule fairWhen(
  String field, {
  required FairPredicate predicate,
  String? reason,
}) {
  return Rule(
    type: 'fairWhen',
    targets: [field],
    evaluate: (values, conditions, [prev, fields, availability]) {
      final value = values[field];

      if (!isSatisfied(value, fields?[field])) {
        return {
          field: const RuleEvaluation(enabled: true, fair: true, reason: null),
        };
      }

      final passed = predicate(value, values, conditions);

      return {
        field: RuleEvaluation(
          enabled: true,
          fair: passed,
          reason: passed
              ? null
              : _resolveReason(
                  reason, values, conditions, 'selection is no longer valid'),
        ),
      };
    },
  );
}
