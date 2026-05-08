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
    this.activeBranch,
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

      final fieldNamesSet = fields.keys.toSet();

      final jsonRules = <JsonRule>[];
      if (json['rules'] != null) {
        final rulesList = json['rules'] as List<dynamic>;
        for (final ruleData in rulesList) {
          final parsed = _parseJsonRule(ruleData as Map<String, dynamic>);
          _validateRuleFields(parsed, fieldNamesSet);
          _validateRuleConditions(parsed, conditions);
          jsonRules.add(parsed);
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
      final op = _parseCheckOp(
          vMap['op'] as String?, vMap['params'] as Map<String, dynamic>?);
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
        if (jsonRule.source == null && jsonRule.when == null) {
          throw UmpireSchemaException(
              'disables rule requires "source", "field", or "when"');
        }
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
        return oneOf(
          jsonRule.group!,
          jsonRule.branches!,
          activeBranch: jsonRule.activeBranch,
          reason: jsonRule.reason,
        );

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
        return eitherOf(
          jsonRule.group!,
          compiledBranches,
          reason: jsonRule.reason,
        );

      case 'anyOf':
        final compiledSubRules = jsonRule.subRuleData!
            .map((raw) {
              final parsed = _parseJsonRule(raw);
              _validateRuleFields(parsed, fieldNamesSet);
              return _buildRule(parsed, fieldNamesSet);
            })
            .toList();
        return anyOf(compiledSubRules);

      default:
        throw UmpireSchemaException(
          'Unknown rule type: "${jsonRule.type}"',
        );
    }
  }
}

void _validateRuleFields(JsonRule rule, Set<String> fieldNames) {
  // Validate field references
  if (rule.field != null && !fieldNames.contains(rule.field)) {
    throw UmpireSchemaException(
        'Unknown field "${rule.field}" in ${rule.type} rule');
  }
  if (rule.source != null && !fieldNames.contains(rule.source)) {
    throw UmpireSchemaException(
        'Unknown field "${rule.source}" in ${rule.type} rule');
  }
  if (rule.targets != null) {
    for (final t in rule.targets!) {
      if (!fieldNames.contains(t)) {
        throw UmpireSchemaException(
            'Unknown field "$t" in ${rule.type} rule');
      }
    }
  }
  if (rule.branches != null) {
    for (final fields in rule.branches!.values) {
      for (final f in fields) {
        if (!fieldNames.contains(f)) {
          throw UmpireSchemaException(
              'Unknown field "$f" in ${rule.type} rule');
        }
      }
    }
  }
  if (rule.when != null) {
    _validateExprFields(rule.when!, fieldNames);
  }
  if (rule.rawBranches != null) {
    for (final subRules in rule.rawBranches!.values) {
      for (final subRule in subRules) {
        _validateExprFieldsInRuleMap(subRule, fieldNames);
      }
    }
  }
  if (rule.subRuleData != null) {
    for (final subRule in rule.subRuleData!) {
      _validateExprFieldsInRuleMap(subRule, fieldNames);
    }
  }
}

void _validateExprFieldsInRuleMap(
    Map<String, dynamic> data, Set<String> fieldNames) {
  if (data['field'] != null && !fieldNames.contains(data['field'])) {
    throw UmpireSchemaException(
        'Unknown field "${data['field']}" in rule expression');
  }
  if (data['when'] != null) {
    _validateExprFields(data['when'] as Map<String, dynamic>, fieldNames);
  }
}

void _validateExprFields(Map<String, dynamic> expr, Set<String> fieldNames) {
  final op = expr['op'] as String?;
  final field = expr['field'] as String?;
  if (field != null && !fieldNames.contains(field)) {
    throw UmpireSchemaException('Unknown field "$field" in expression');
  }

  // Validate check expressions eagerly for invalid regex patterns
  if (op == 'check') {
    final check = expr['check'] as Map<String, dynamic>?;
    if (check != null) {
      final checkOp = check['op'] as String?;
      if (checkOp == 'matches') {
        final pattern = check['pattern'] as String?;
        if (pattern != null) {
          try {
            RegExp(pattern);
          } on FormatException catch (e) {
            throw UmpireSchemaException(
                'Invalid regex pattern in check expression: ${e.message}');
          }
        }
      }
    }
  }

  final exprs = expr['exprs'] as List?;
  if (exprs != null) {
    for (final e in exprs) {
      _validateExprFields(e as Map<String, dynamic>, fieldNames);
    }
  }

  final subExpr = expr['expr'] as Map<String, dynamic>?;
  if (subExpr != null) {
    _validateExprFields(subExpr, fieldNames);
  }
}

void _validateRuleConditions(
    JsonRule rule, Map<String, ConditionDef> conditions) {
  if (rule.when != null) {
    _validateExprConditions(rule.when!, conditions);
  }
  if (rule.rawBranches != null) {
    for (final subRules in rule.rawBranches!.values) {
      for (final subRule in subRules) {
        if (subRule['when'] != null) {
          _validateExprConditions(
              subRule['when'] as Map<String, dynamic>, conditions);
        }
      }
    }
  }
  if (rule.subRuleData != null) {
    for (final subRule in rule.subRuleData!) {
      if (subRule['when'] != null) {
        _validateExprConditions(
            subRule['when'] as Map<String, dynamic>, conditions);
      }
    }
  }
}

void _validateExprConditions(
    Map<String, dynamic> expr, Map<String, ConditionDef> conditions) {
  final op = expr['op'] as String?;
  final condition = expr['condition'] as String?;

  if (op == 'fieldInCond' && condition != null) {
    final condDef = conditions[condition];
    if (condDef == null || !condDef.type.endsWith('[]')) {
      throw UmpireSchemaException(
        '"fieldInCond" expression references condition "$condition", '
        'which must be an array condition.',
      );
    }
  }

  final exprs = expr['exprs'] as List?;
  if (exprs != null) {
    for (final e in exprs) {
      _validateExprConditions(e as Map<String, dynamic>, conditions);
    }
  }

  final subExpr = expr['expr'] as Map<String, dynamic>?;
  if (subExpr != null) {
    _validateExprConditions(subExpr, conditions);
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
        source: (data['field'] ?? data['source']) as String?,
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
      var params = data['params'] as Map<String, dynamic>?;
      // Conformance fixtures use flat params at the rule level
      if (params == null && data.containsKey('pattern')) {
        params = data;
      }
      if (params == null && data.containsKey('value')) {
        params = data;
      }
      if (params == null && data.containsKey('min')) {
        params = data;
      }
      return JsonRule(
        type: type,
        field: data['field'] as String?,
        op: op,
        reason: data['reason'] as String?,
        validator: _parseCheckOp(op, params),
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
        reason: data['reason'] as String?,
        rawBranches: rawBranches,
      );

    case 'anyOf':
      final rulesList = data['rules'] as List<dynamic>?;
      return JsonRule(
        type: type,
        reason: data['reason'] as String?,
        subRuleData:
            (rulesList ?? []).cast<Map<String, dynamic>>(),
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
      final pattern = params?['pattern'] as String?;
      if (pattern == null) {
        throw UmpireSchemaException(
          'Check "matches" requires "pattern"',
        );
      }
      return checkOps.matches(RegExp(pattern));
    case 'minLength':
      final min = params?['min'] ?? params?['value'];
      if (min == null) {
        throw UmpireSchemaException(
          'Check "minLength" requires "min" or "value"',
        );
      }
      return checkOps.minLength(min as int);
    case 'maxLength':
      final max = params?['max'] ?? params?['value'];
      if (max == null) {
        throw UmpireSchemaException(
          'Check "maxLength" requires "max" or "value"',
        );
      }
      return checkOps.maxLength(max as int);
    case 'min':
      final minVal = params?['min'] ?? params?['value'];
      if (minVal == null) {
        throw UmpireSchemaException('Check "min" requires "min" or "value"');
      }
      return checkOps.min(minVal as num);
    case 'max':
      final maxVal = params?['max'] ?? params?['value'];
      if (maxVal == null) {
        throw UmpireSchemaException('Check "max" requires "max" or "value"');
      }
      return checkOps.max(maxVal as num);
    case 'range':
      if (params == null || params['min'] == null || params['max'] == null) {
        throw UmpireSchemaException(
          'Check "range" requires "min" and "max"',
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
