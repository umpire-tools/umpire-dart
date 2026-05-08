import 'dart:async';

import '../check_ops.dart';
import '../field_def.dart';
import '../rules/check.dart';
import '../rules/disables.dart';
import '../rules/one_of.dart';
import '../rules/requires.dart';
import '../rules/rule.dart';
import '../umpire.dart';
import 'condition_provider.dart';
import 'expr.dart';

class UmpireSchemaException implements Exception {
  final String message;
  UmpireSchemaException(this.message);

  @override
  String toString() => 'UmpireSchemaException: $message';
}

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
  final String? activeBranch;
  final List<String>? targets;
  final String? source;
  final String? op;
  final String? dependency;
  final dynamic validator;

  const JsonRule({
    required this.type,
    this.field,
    this.when,
    this.reason,
    this.group,
    this.branches,
    this.activeBranch,
    this.targets,
    this.source,
    this.op,
    this.dependency,
    this.validator,
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
    try {
      final version = json['version'];
      if (version == null || version != 1) {
        throw UmpireSchemaException(
          'Unsupported schema version $version. '
          'This runtime supports version 1.',
        );
      }

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
            defaultValue: fieldMap['defaultValue'],
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
        version: version as int,
        conditions: conditions,
        fields: fields,
        rules: jsonRules,
        validators: validators,
        excluded: excludedList,
      );
    } on TypeError catch (e) {
      throw UmpireSchemaException('Invalid schema format: $e');
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
      switch (jsonRule.type) {
        case 'requires':
          if (jsonRule.dependency != null) {
            compiledRules.add(requires(
              jsonRule.field!,
              dependency: jsonRule.dependency,
              reason: jsonRule.reason,
            ));
          } else if (jsonRule.when != null) {
            final predicate = compileExpr(
              jsonRule.when!,
              fieldNames: fieldNamesSet,
            );
            compiledRules.add(requires(
              jsonRule.field!,
              when: predicate,
              reason: jsonRule.reason,
            ));
          }
          break;

        case 'enabledWhen':
          final predicate = compileExpr(
            jsonRule.when!,
            fieldNames: fieldNamesSet,
          );
          compiledRules.add(enabledWhen(
            jsonRule.field!,
            predicate: predicate,
            reason: jsonRule.reason,
          ));
          break;

        case 'fairWhen':
          final predicate = compileExpr(
            jsonRule.when!,
            fieldNames: fieldNamesSet,
          );
          compiledRules.add(fairWhen(
            jsonRule.field!,
            predicate: (value, values, conds) => predicate(values, conds),
            reason: jsonRule.reason,
          ));
          break;

        case 'disables':
          if (jsonRule.when != null) {
            final predicate = compileExpr(
              jsonRule.when!,
              fieldNames: fieldNamesSet,
            );
            compiledRules.add(disables(
              jsonRule.source!,
              jsonRule.targets!,
              when: predicate,
              reason: jsonRule.reason,
            ));
          } else {
            compiledRules.add(disables(
              jsonRule.source!,
              jsonRule.targets!,
              reason: jsonRule.reason,
            ));
          }
          break;

        case 'oneOf':
          compiledRules.add(oneOf(
            jsonRule.group!,
            jsonRule.branches!,
            activeBranch: jsonRule.activeBranch,
            reason: jsonRule.reason,
          ));
          break;

        case 'check':
          final checkPredicate = check(jsonRule.field!, jsonRule.validator);
          compiledRules.add(fairWhen(
            jsonRule.field!,
            predicate: (value, values, conds) => checkPredicate(values, conds),
            reason: jsonRule.reason,
          ));
          break;

        default:
          throw UmpireSchemaException(
            'Unknown rule type: "${jsonRule.type}"',
          );
      }
    }

    final allRules = [...compiledRules, ...rules];

    return umpire(fields: fields, rules: allRules);
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
    default:
      return IsEmptyStrategy.present;
  }
}

JsonRule _parseJsonRule(Map<String, dynamic> data) {
  final type = data['type'] as String;

  switch (type) {
    case 'requires':
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
        source: data['field'] as String?,
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
        activeBranch: data['activeBranch'] as String?,
        reason: data['reason'] as String?,
      );

    case 'check':
      final op = data['op'] as String?;
      final params = data['params'] as Map<String, dynamic>?;
      return JsonRule(
        type: type,
        field: data['field'] as String?,
        op: op,
        reason: data['reason'] as String?,
        validator: _parseCheckOp(op, params),
      );

    default:
      throw UmpireSchemaException('Unknown rule type: "$type"');
  }
}

CheckOp _parseCheckOp(String? op, Map<String, dynamic>? params) {
  if (op == null) {
    throw UmpireSchemaException('Check rule missing "op" field');
  }

  switch (op) {
    case 'email':
      return checkOps.email();
    case 'url':
      return checkOps.url();
    case 'matches':
      if (params == null || params['pattern'] == null) {
        throw UmpireSchemaException(
          'Check "matches" requires "params.pattern"',
        );
      }
      return checkOps.matches(RegExp(params['pattern'] as String));
    case 'minLength':
      if (params == null || params['min'] == null) {
        throw UmpireSchemaException(
          'Check "minLength" requires "params.min"',
        );
      }
      return checkOps.minLength(params['min'] as int);
    case 'maxLength':
      if (params == null || params['max'] == null) {
        throw UmpireSchemaException(
          'Check "maxLength" requires "params.max"',
        );
      }
      return checkOps.maxLength(params['max'] as int);
    case 'min':
      if (params == null || params['min'] == null) {
        throw UmpireSchemaException('Check "min" requires "params.min"');
      }
      return checkOps.min(params['min'] as num);
    case 'max':
      if (params == null || params['max'] == null) {
        throw UmpireSchemaException('Check "max" requires "params.max"');
      }
      return checkOps.max(params['max'] as num);
    case 'range':
      if (params == null ||
          params['min'] == null ||
          params['max'] == null) {
        throw UmpireSchemaException(
          'Check "range" requires "params.min" and "params.max"',
        );
      }
      return checkOps.range(
        params['min'] as num,
        params['max'] as num,
      );
    case 'integer':
      return checkOps.integer();
    default:
      throw UmpireSchemaException('Unknown check op: "$op"');
  }
}
