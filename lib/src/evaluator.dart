import 'availability.dart';
import 'field_def.dart';
import 'rules/rule.dart';
import 'satisfaction.dart';

/// Partitions rules into gate (enabled) and fair phases.
class _RulePhaseBuckets {
  final List<Rule> gateRules;
  final List<Rule> fairRules;

  const _RulePhaseBuckets({required this.gateRules, required this.fairRules});

  static const empty = _RulePhaseBuckets(gateRules: [], fairRules: []);
}

Map<String, _RulePhaseBuckets> _indexRulesByTargetPhase(
  Map<String, List<Rule>> rulesByTarget,
) {
  final result = <String, _RulePhaseBuckets>{};

  for (final entry in rulesByTarget.entries) {
    final gateRules = <Rule>[];
    final fairRules = <Rule>[];

    for (final rule in entry.value) {
      if (rule.type == 'fairWhen') {
        fairRules.add(rule);
      } else {
        gateRules.add(rule);
      }
    }

    result[entry.key] = _RulePhaseBuckets(
      gateRules: gateRules,
      fairRules: fairRules,
    );
  }

  return result;
}

Map<String, List<Rule>> _indexRulesByTarget(List<Rule> rules) {
  final result = <String, List<Rule>>{};

  for (final rule in rules) {
    for (final target in rule.targets) {
      result.putIfAbsent(target, () => []).add(rule);
    }
  }

  return result;
}

RuleEvaluation _evaluateRuleForField(
  Rule rule,
  String field,
  Map<String, FieldDef> fields,
  Map<String, dynamic> values,
  Map<String, dynamic> conditions,
  Map<String, dynamic>? prev,
  AvailabilityMap availability,
  Map<Rule, Map<String, RuleEvaluation>> baseRuleCache,
) {
  // Check cache first
  if (baseRuleCache.containsKey(rule)) {
    final cached = baseRuleCache[rule]![field];
    if (cached != null) return cached;
  }

  final evaluation = rule.evaluate(values, conditions, prev, fields, availability);
  baseRuleCache[rule] = evaluation;
  return evaluation[field] ?? const RuleEvaluation(enabled: true, reason: null);
}

/// Evaluates all fields in topological order, applying rules.
AvailabilityMap evaluate(
  Map<String, FieldDef> fields,
  List<Rule> rules,
  List<String> topoOrder,
  Map<String, dynamic> values,
  Map<String, dynamic> conditions, [
  Map<String, dynamic>? prev,
]) {
  final availability = <String, FieldAvailability>{};
  final baseRuleCache = <Rule, Map<String, RuleEvaluation>>{};
  final rulesByTarget = _indexRulesByTarget(rules);
  final rulesByTargetPhase = _indexRulesByTargetPhase(rulesByTarget);

  for (final field in topoOrder) {
    final buckets = rulesByTargetPhase[field] ?? _RulePhaseBuckets.empty;
    final reasons = <String>[];
    var enabled = true;
    var fair = true;
    String? reason;

    // Phase 1: gate rules (enabled/disabled)
    for (final rule in buckets.gateRules) {
      final result = _evaluateRuleForField(
        rule, field, fields, values, conditions, prev,
        availability, baseRuleCache,
      );

      if (result.enabled) continue;

      enabled = false;
      reason ??= result.reason;
      _collectReasons(result, reasons);
    }

    // Phase 2: fair rules (only evaluated if enabled)
    if (enabled) {
      for (final rule in buckets.fairRules) {
        final result = _evaluateRuleForField(
          rule, field, fields, values, conditions, prev,
          availability, baseRuleCache,
        );

        if (result.fair != false) continue;

        fair = false;
        reason ??= result.reason;
        _collectReasons(result, reasons);
      }
    }

    final fieldDef = fields[field];
    final satisfied = isSatisfied(values[field], fieldDef);
    final required = enabled ? (fieldDef?.required ?? false) : false;

    availability[field] = FieldAvailability(
      enabled: enabled,
      required: required,
      fair: fair,
      satisfied: satisfied,
      reason: reason,
      reasons: reasons,
    );
  }

  return availability;
}

void _collectReasons(RuleEvaluation result, List<String> reasons) {
  if (result.reasons != null && result.reasons!.isNotEmpty) {
    reasons.addAll(result.reasons!);
    return;
  }
  if (result.reason != null) {
    reasons.add(result.reason!);
  }
}
