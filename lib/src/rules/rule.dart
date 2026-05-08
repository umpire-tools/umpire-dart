import '../availability.dart';
import '../field_def.dart';

/// Predicate signature — used by conditional rules.
typedef Predicate = bool Function(
  Map<String, dynamic> values,
  Map<String, dynamic> conditions,
);

/// FairWhen predicate — receives the field value, all values, and conditions.
typedef FairPredicate = bool Function(
  dynamic value,
  Map<String, dynamic> values,
  Map<String, dynamic> conditions,
);

/// A rule's per-target evaluation result.
class RuleEvaluation {
  final bool enabled;
  final bool? fair;
  final String? reason;
  final List<String>? reasons;

  const RuleEvaluation({
    required this.enabled,
    this.fair,
    this.reason,
    this.reasons,
  });
}

/// Signature for rule evaluation functions.
typedef RuleEvaluator = Map<String, RuleEvaluation> Function(
  Map<String, dynamic> values,
  Map<String, dynamic> conditions, [
  Map<String, dynamic>? prev,
  Map<String, FieldDef>? fields,
  AvailabilityMap? availability,
]);

/// The base rule type. Each rule targets one or more fields.
class Rule {
  final String type;
  final List<String> targets;
  final List<String> sources;
  final String constraint;
  final RuleEvaluator evaluate;

  const Rule({
    required this.type,
    required this.targets,
    this.sources = const [],
    this.constraint = 'enabled',
    required this.evaluate,
  });
}
