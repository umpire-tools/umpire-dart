import 'dart:async';

import '../check_ops.dart';
import '../field_def.dart';
import '../rules/any_of.dart';
import '../rules/check.dart';
import '../rules/disables.dart';
import '../rules/either_of.dart';
import '../rules/one_of.dart';
import '../rules/requires.dart';
import '../rules/rule.dart';
import '../umpire.dart';
import 'check_op.dart';
import 'condition_provider.dart';
import 'errors.dart';
import 'expr.dart';
import 'validate.dart';

export 'errors.dart';

class ConditionDef {
  final String type;
  const ConditionDef({required this.type});
}

class JsonRule {
  final String type;
  final String? field;
  final Map<String, dynamic>? when;
  final String? reason;
  final String? group;
  final Map<String, List<String>>? branches;
  final List<String>? targets;
  final String? source;
  final String? op;
  final String? dependency;
  final List<dynamic>? dependencies;
  final dynamic validator;
  final Map<String, List<Map<String, dynamic>>>? rawBranches;
  final List<Map<String, dynamic>>? subRuleData;

  const JsonRule({
    required this.type,
    this.field,
    this.when,
    this.reason,
    this.group,
    this.branches,
    this.targets,
    this.source,
    this.op,
    this.dependency,
    this.dependencies,
    this.validator,
    this.rawBranches,
    this.subRuleData,
  });
}

class UmpireSchema {
  final int version;
  final Map<String, ConditionDef> conditions;
  final Map<String, FieldDef> fields;
  final List<JsonRule> rules;
  final Map<String, dynamic> validators;
  final List<Map<String, dynamic>> excluded;

  UmpireSchema._({
    required this.version,
    required this.conditions,
    required this.fields,
    required this.rules,
    required this.validators,
    required this.excluded,
  });

  factory UmpireSchema.fromJson(Map<String, dynamic> json) {
    validateSchemaJson(json);

    try {
      final conditions = <String, ConditionDef>{};
      if (json['conditions'] != null) {
        final condsJson = json['conditions'] as Map<String, dynamic>;
        for (final entry in condsJson.entries) {
          final condMap = entry.value as Map<String, dynamic>;
          conditions[entry.key] = ConditionDef(
            type: condMap['type'] as String,
          );
        }
      }

      final fields = <String, FieldDef>{};
      if (json['fields'] != null) {
        final fieldsJson = json['fields'] as Map<String, dynamic>;
        for (final entry in fieldsJson.entries) {
          final fieldMap = entry.value as Map<String, dynamic>;
          fields[entry.key] = FieldDef(
            required: fieldMap['required'] as bool? ?? false,
            defaultValue: fieldMap['default'],
            isEmpty: _parseIsEmptyStrategy(fieldMap['isEmpty'] as String?),
          );
        }
      }

      final jsonRules = <JsonRule>[];
      if (json['rules'] != null) {
        final rulesList = json['rules'] as List<dynamic>;
        for (final ruleData in rulesList) {
          jsonRules.add(_parseJsonRule(ruleData as Map<String, dynamic>));
        }
      }

      final validators =
          (json['validators'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      final excludedList = <Map<String, dynamic>>[];
      if (json['excluded'] != null) {
        final excludedJson = json['excluded'] as List<dynamic>;
        for (final entry in excludedJson) {
          final entryMap = entry as Map<String, dynamic>;
          excludedList.add(entryMap);
          print(
            '[umpire] Rule "${entryMap['type']}" for field '
            '"${entryMap['field']}" excluded from schema: '
            '${entryMap['description']}. Implement an equivalent rule natively.',
          );
        }
      }

      return UmpireSchema._(
        version: json['version'] as int,
        conditions: conditions,
        fields: fields,
        rules: jsonRules,
        validators: validators,
        excluded: excludedList,
      );
    } on TypeError catch (e) {
      throw UmpireSchemaException('Invalid schema format: $e');
    } on FormatException catch (e) {
      throw UmpireSchemaException('Invalid regex pattern: ${e.message}');
    }
  }

  Umpire build({
    Map<String, ConditionProvider>? conditions,
    List<Rule> rules = const [],
  }) {
    final fieldNamesSet = fields.keys.toSet();

    final resolvedConditions = <String, dynamic>{};
    if (conditions != null) {
      for (final entry in conditions.entries) {
        final provider = entry.value;
        if (provider.value != null) {
          resolvedConditions[entry.key] = provider.value;
        } else if (provider.resolver != null) {
          try {
            final result = provider.resolver!();
            if (result is Future) {
              throw UmpireSchemaException(
                'Condition "${entry.key}" returned a Future. Async conditions '
                'must be resolved before calling build(). Use '
                'ConditionProvider.value() for sync values.',
              );
            } else {
              resolvedConditions[entry.key] = result;
            }
          } catch (e) {
            if (e is UmpireSchemaException) rethrow;
            throw UmpireSchemaException(
              'Condition "${entry.key}" resolver threw an error: $e',
            );
          }
        }
      }
    }

    final compiledRules = <Rule>[];
    for (final jsonRule in this.rules) {
      compiledRules.add(_buildRule(jsonRule, fieldNamesSet));
    }

    final allRules = [...compiledRules, ...rules];

    final compiledValidators = <String, ValidatorEntry>{};
    for (final entry in validators.entries) {
      final vMap = entry.value as Map<String, dynamic>?;
      if (vMap == null) continue;
      final op = parseCheckOp(vMap['op'] as String?, vMap);
      compiledValidators[entry.key] = ValidatorEntry(
        op: op,
        error: vMap['error'] as String? ?? 'Invalid value',
      );
    }

    return umpire(
        fields: fields, rules: allRules, validators: compiledValidators);
  }

  Rule _buildRule(JsonRule jsonRule, Set<String> fieldNamesSet) {
    switch (jsonRule.type) {
      case 'requires':
        if (jsonRule.dependencies != null && jsonRule.dependencies!.isNotEmpty) {
          // Build a compound predicate that ANDs all dependencies
          final deps = jsonRule.dependencies!.map((d) {
            if (d is String) {
              // Field dependency — satisfied if value is non-null
              return (Map<String, dynamic> values, Map<String, dynamic> conds) {
                return values.containsKey(d) && values[d] != null;
              };
            }
            // Expression dependency
            return compileExpr(
              d as Map<String, dynamic>,
              fieldNames: fieldNamesSet,
            );
          }).toList();

          final combinedPredicate = (Map<String, dynamic> values,
              Map<String, dynamic> conds) {
            return deps.every((p) => p(values, conds));
          };

          return requires(
            jsonRule.field!,
            when: combinedPredicate,
            reason: jsonRule.reason,
          );
        }
        if (jsonRule.dependency != null) {
          return requires(
            jsonRule.field!,
            dependency: jsonRule.dependency,
            reason: jsonRule.reason,
          );
        } else if (jsonRule.when != null) {
          final predicate = compileExpr(
            jsonRule.when!,
            fieldNames: fieldNamesSet,
          );
          return requires(
            jsonRule.field!,
            when: predicate,
            reason: jsonRule.reason,
          );
        }
        throw UmpireSchemaException('requires rule missing dependency or when');

      case 'enabledWhen':
        final predicate = compileExpr(
          jsonRule.when!,
          fieldNames: fieldNamesSet,
        );
        return enabledWhen(
          jsonRule.field!,
          predicate: predicate,
          reason: jsonRule.reason,
        );

      case 'fairWhen':
        final predicate = compileExpr(
          jsonRule.when!,
          fieldNames: fieldNamesSet,
        );
        return fairWhen(
          jsonRule.field!,
          predicate: (value, values, conds) => predicate(values, conds),
          reason: jsonRule.reason,
        );

      case 'disables':
        if (jsonRule.targets == null || jsonRule.targets!.isEmpty) {
          throw UmpireSchemaException(
              'disables rule requires non-empty "targets"');
        }
        if (jsonRule.when != null) {
          final predicate = compileExpr(
            jsonRule.when!,
            fieldNames: fieldNamesSet,
          );
          return disables(
            jsonRule.source,
            jsonRule.targets!,
            when: predicate,
            reason: jsonRule.reason,
          );
        }
        return disables(
          jsonRule.source,
          jsonRule.targets!,
          reason: jsonRule.reason,
        );

      case 'oneOf':
        return oneOf(jsonRule.group!, jsonRule.branches!);

      case 'check':
        final op = jsonRule.validator as CheckOp;
        final checkPredicate = check(jsonRule.field!, op);
        return fairWhen(
          jsonRule.field!,
          predicate: (value, values, conds) => checkPredicate(values, conds),
          reason: jsonRule.reason ?? op.reason,
        );

      case 'eitherOf':
        final compiledBranches = <String, List<Rule>>{};
        for (final entry in jsonRule.rawBranches!.entries) {
          compiledBranches[entry.key] = entry.value
              .map((subRuleJson) {
                final parsed = _parseJsonRule(subRuleJson);
                return _buildRule(parsed, fieldNamesSet);
              })
              .toList();
        }
        return eitherOf(jsonRule.group!, compiledBranches);

      case 'anyOf':
        final compiledSubRules = jsonRule.subRuleData!
            .map((raw) => _buildRule(_parseJsonRule(raw), fieldNamesSet))
            .toList();
        return anyOf(compiledSubRules);

      default:
        throw UmpireSchemaException(
          'Unknown rule type: "${jsonRule.type}"',
        );
    }
  }
}

IsEmptyStrategy _parseIsEmptyStrategy(String? value) {
  if (value == null) return IsEmptyStrategy.present;
  switch (value) {
    case 'string':
      return IsEmptyStrategy.string;
    case 'number':
      return IsEmptyStrategy.number;
    case 'boolean':
      return IsEmptyStrategy.boolean;
    case 'array':
      return IsEmptyStrategy.array;
    case 'object':
      return IsEmptyStrategy.object;
    default:
      return IsEmptyStrategy.present;
  }
}

JsonRule _parseJsonRule(Map<String, dynamic> data) {
  final type = data['type'] as String;

  switch (type) {
    case 'requires':
      if (data.containsKey('dependencies')) {
        return JsonRule(
          type: type,
          field: data['field'] as String?,
          dependencies: data['dependencies'] as List<dynamic>?,
          reason: data['reason'] as String?,
        );
      }
      if (data.containsKey('dependency')) {
        return JsonRule(
          type: type,
          field: data['field'] as String?,
          dependency: data['dependency'] as String?,
          reason: data['reason'] as String?,
        );
      }
      return JsonRule(
        type: type,
        field: data['field'] as String?,
        when: data['when'] as Map<String, dynamic>?,
        reason: data['reason'] as String?,
      );

    case 'enabledWhen':
    case 'fairWhen':
      return JsonRule(
        type: type,
        field: data['field'] as String?,
        when: data['when'] as Map<String, dynamic>?,
        reason: data['reason'] as String?,
      );

    case 'disables':
      return JsonRule(
        type: type,
        source: data['source'] as String?,
        targets: (data['targets'] as List<dynamic>?)?.cast<String>(),
        when: data['when'] as Map<String, dynamic>?,
        reason: data['reason'] as String?,
      );

    case 'oneOf':
      final branchesJson = data['branches'] as Map<String, dynamic>;
      final branches = branchesJson.map(
        (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()),
      );
      return JsonRule(
        type: type,
        group: data['group'] as String?,
        branches: branches,
      );

    case 'check':
      // Check parameters are flat on the rule and validator spec.
      final op = data['op'] as String?;
      return JsonRule(
        type: type,
        field: data['field'] as String?,
        op: op,
        reason: data['reason'] as String?,
        validator: parseCheckOp(op, data),
      );

    case 'eitherOf':
      final branchesJson = data['branches'] as Map<String, dynamic>;
      final rawBranches = <String, List<Map<String, dynamic>>>{};
      for (final entry in branchesJson.entries) {
        rawBranches[entry.key] =
            (entry.value as List<dynamic>).cast<Map<String, dynamic>>();
      }
      return JsonRule(
        type: type,
        group: data['group'] as String?,
        rawBranches: rawBranches,
      );

    case 'anyOf':
      final rulesList = data['rules'] as List<dynamic>?;
      return JsonRule(
        type: type,
        subRuleData:
            (rulesList ?? []).cast<Map<String, dynamic>>(),
      );

    default:
      throw UmpireSchemaException('Unknown rule type: "$type"');
  }
}
