import 'availability.dart';
import 'equality.dart';
import 'evaluator.dart' as eval;
import 'field_def.dart';
import 'graph.dart';
import 'rules/rule.dart';

/// The core form validation engine.
///
/// Build rules with the rule constructors and pass them to [umpire].
class Umpire {
  final Map<String, FieldDef> _fields;
  final List<Rule> _rules;
  final List<String> _fieldNames;
  final List<String> _topoOrder;

  Umpire._({
    required Map<String, FieldDef> fields,
    required List<Rule> rules,
  })  : _fields = fields,
        _rules = rules,
        _fieldNames = fields.keys.toList(),
        _topoOrder = _computeTopoOrder(fields, rules);

  static List<String> _computeTopoOrder(
    Map<String, FieldDef> fields,
    List<Rule> rules,
  ) {
    final graph = buildGraph(fields, rules);
    detectCycles(graph);
    return topologicalSort(graph, fields.keys.toList());
  }

  /// Evaluates all rules against [values] and optional [conditions], returning
  /// per-field availability.
  AvailabilityMap check(
    Map<String, dynamic> values, {
    Map<String, dynamic> conditions = const {},
  }) {
    return eval.evaluate(
      _fields,
      _rules,
      _topoOrder,
      values,
      conditions,
    );
  }

  /// Computes recommended fouls when transitioning from [before] to [after].
  ///
  /// A foul is raised when a field transitions from enabled→disabled or
  /// fair→unfair, provided the field is still satisfied and the current
  /// value differs from the field's default.
  List<Foul> play({
    required AvailabilityMap before,
    required AvailabilityMap after,
    required Map<String, dynamic> values,
  }) {
    final recommendations = <Foul>[];

    for (final field in _fieldNames) {
      final beforeStatus = before[field];
      final afterStatus = after[field];

      if (beforeStatus == null || afterStatus == null) continue;

      final disabledTransition = beforeStatus.enabled && !afterStatus.enabled;
      final foulTransition = beforeStatus.fair && afterStatus.fair == false;

      if (!disabledTransition && !foulTransition) continue;

      if (!afterStatus.satisfied) continue;

      final currentValue = values[field];
      final suggestedValue = _fields[field]?.defaultValue;

      if (isEqual(currentValue, suggestedValue)) continue;

      recommendations.add(Foul(
        field: field,
        reason: afterStatus.reason ??
            (disabledTransition ? 'field disabled' : 'field fouled'),
        suggestedValue: suggestedValue,
      ));
    }

    return recommendations;
  }

  /// Initializes field values from defaults, merged with optional [overrides].
  Map<String, dynamic> init([Map<String, dynamic>? overrides]) {
    final values = <String, dynamic>{};

    for (final field in _fieldNames) {
      if (overrides != null && overrides.containsKey(field)) {
        values[field] = overrides[field];
      } else {
        values[field] = _fields[field]?.defaultValue;
      }
    }

    return values;
  }

  /// Returns the topological order of fields.
  List<String> get topoOrder => List.unmodifiable(_topoOrder);
}

/// Creates an [Umpire] instance from field definitions and rules.
///
/// ```dart
/// final ump = umpire(
///   fields: {
///     'email': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
///     'accountType': FieldDef(required: true, defaultValue: 'personal'),
///   },
///   rules: [
///     requires('companyName', dependency: 'accountType'),
///     enabledWhen('vatNumber', predicate: (v, c) => v['accountType'] == 'business'),
///   ],
/// );
/// ```
Umpire umpire({
  required Map<String, FieldDef> fields,
  required List<Rule> rules,
}) {
  _validateRules(fields, rules);
  return Umpire._(fields: fields, rules: rules);
}

void _validateRules(Map<String, FieldDef> fields, List<Rule> rules) {
  final fieldNames = fields.keys.toSet();

  for (final rule in rules) {
    for (final target in rule.targets) {
      if (!fieldNames.contains(target)) {
        throw ArgumentError(
          'Unknown field "$target" referenced by ${rule.type} rule',
        );
      }
    }
    for (final source in rule.sources) {
      if (!fieldNames.contains(source)) {
        throw ArgumentError(
          'Unknown field "$source" referenced by ${rule.type} rule',
        );
      }
    }
  }
}
