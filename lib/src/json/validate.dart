import 'check_op.dart';
import 'errors.dart';
import 'expr.dart';

/// Closed member lists for every object in a v1 schema document.
const _schemaMembers = <String>[
  'version',
  'conditions',
  'fields',
  'rules',
  'validators',
  'excluded',
];

const _conditionTypes = <String>{
  'boolean',
  'string',
  'number',
  'string[]',
  'number[]',
};

const _isEmptyStrategies = <String>{
  'string',
  'number',
  'boolean',
  'array',
  'object',
  'present',
};

const _validatorSpecMemberSets = <String, List<String>>{
  'matches': ['op', 'pattern'],
  'minLength': ['op', 'value'],
  'maxLength': ['op', 'value'],
  'min': ['op', 'value'],
  'max': ['op', 'value'],
  'range': ['op', 'min', 'max'],
};

/// Validates [schema] against the closed Umpire v1 document contract.
///
/// Throws [UmpireSchemaException] for any undeclared member, unknown variant,
/// malformed field reference, or missing required member.
void validateSchemaJson(Map<String, dynamic> schema) {
  _assertKnownMembers(schema, _schemaMembers, 'Schema');

  if (!schema.containsKey('version')) {
    throw UmpireSchemaException(
      'Schema must include a "version" field',
    );
  }
  if (schema['version'] != 1) {
    throw UmpireSchemaException(
      'Unsupported schema version "${schema['version']}"',
    );
  }

  final conditions = _optionalRecord(schema, 'conditions', 'Schema');
  final fields = _record(schema, 'fields', 'Schema');
  if (fields.isEmpty) {
    throw UmpireSchemaException('Schema must include at least one field');
  }
  final rules = _array(schema, 'rules', 'Schema');
  final validators = _optionalRecord(schema, 'validators', 'Schema');
  final excluded = _optionalArray(schema, 'excluded', 'Schema');

  final conditionTypes = <String, String>{};
  for (final entry in (conditions ?? const {}).entries) {
    conditionTypes[entry.key] = _validateConditionDef(entry.key, entry.value);
  }

  for (final entry in fields.entries) {
    _validateFieldDef(entry.key, entry.value);
  }

  final fieldNames = fields.keys.toSet();
  for (final rule in rules) {
    _validateRule(rule, fieldNames, conditionTypes);
  }

  for (final entry in (validators ?? const {}).entries) {
    _validateValidatorDef(entry.key, entry.value, fieldNames);
  }

  for (final rule in excluded ?? const <dynamic>[]) {
    _validateExcludedRule(rule);
  }
}

String _validateConditionDef(String name, dynamic definition) {
  final record = _asRecord(definition, 'condition definition for "$name"');
  _assertKnownMembers(
    record,
    const ['type', 'description'],
    'condition definition for "$name"',
  );

  final type = record['type'];
  if (type is! String || !_conditionTypes.contains(type)) {
    throw UmpireSchemaException(
      'condition "$name" must use a supported type',
    );
  }
  if (record.containsKey('description') && record['description'] is! String) {
    throw UmpireSchemaException(
      'condition "$name" description must be a string when provided',
    );
  }

  return type;
}

void _validateFieldDef(String name, dynamic definition) {
  final record = _asRecord(definition, 'field definition for "$name"');
  _assertKnownMembers(
    record,
    const ['required', 'default', 'isEmpty'],
    'field definition for "$name"',
  );

  if (record.containsKey('required') && record['required'] is! bool) {
    throw UmpireSchemaException(
      'field definition for "$name" required must be a boolean when provided',
    );
  }
  if (record.containsKey('default') && !_isJsonPrimitive(record['default'])) {
    throw UmpireSchemaException(
      'field definition for "$name" has a non-serializable "default" value',
    );
  }
  final isEmpty = record['isEmpty'];
  if (record.containsKey('isEmpty') &&
      (isEmpty is! String || !_isEmptyStrategies.contains(isEmpty))) {
    throw UmpireSchemaException(
      'Unknown isEmpty strategy "$isEmpty" on field "$name"',
    );
  }
}

void _validateRule(
  dynamic rule,
  Set<String> fieldNames,
  Map<String, String> conditionTypes,
) {
  final record = _asRecord(rule, 'Rule');
  final type = record['type'];
  if (type is! String) {
    throw UmpireSchemaException('Rule must include a string "type"');
  }

  _assertKnownMembers(record, _ruleMembers(record), 'Rule "$type"');

  if (record.containsKey('reason') && record['reason'] is! String) {
    throw UmpireSchemaException('Rule "$type" reason must be a string');
  }

  switch (type) {
    case 'requires':
      _validateRequiresRule(record, fieldNames, conditionTypes);
    case 'enabledWhen':
    case 'fairWhen':
      _assertField(record['field'], fieldNames, 'Rule "$type"');
      _validateExprRoot(record['when'], fieldNames, conditionTypes);
    case 'disables':
      _validateDisablesRule(record, fieldNames, conditionTypes);
    case 'oneOf':
      _assertString(record['group'], 'Rule "oneOf" group');
      _validateOneOfBranches(record, fieldNames);
    case 'eitherOf':
      _assertString(record['group'], 'Rule "eitherOf" group');
      final branches = _record(record, 'branches', 'Rule "eitherOf"');
      final names = branches.keys.toList();
      if (names.isEmpty) {
        throw UmpireSchemaException(
          'eitherOf("${record['group']}") must include at least one branch',
        );
      }
      for (final name in names) {
        final branchRules = _asList(
          branches[name],
          'Rule "eitherOf" branch "$name"',
        );
        if (branchRules.isEmpty) {
          throw UmpireSchemaException(
            'eitherOf("${record['group']}") branch "$name" must not be empty',
          );
        }
        for (final inner in branchRules) {
          _validateRule(inner, fieldNames, conditionTypes);
        }
      }
    case 'anyOf':
      final innerRules = _array(record, 'rules', 'Rule "anyOf"');
      if (innerRules.isEmpty) {
        throw UmpireSchemaException('anyOf() requires at least one rule');
      }
      for (final inner in innerRules) {
        _validateRule(inner, fieldNames, conditionTypes);
      }
    case 'check':
      _assertField(record['field'], fieldNames, 'Rule "check"');
      _validateValidatorSpec(record, const ['type', 'field', 'reason']);
  }
}

List<String> _ruleMembers(Map<String, dynamic> rule) {
  switch (rule['type']) {
    case 'requires':
      if (rule.containsKey('dependency')) {
        return const ['type', 'field', 'dependency', 'reason'];
      }
      if (rule.containsKey('dependencies')) {
        return const ['type', 'field', 'dependencies', 'reason'];
      }
      return const ['type', 'field', 'when', 'reason'];
    case 'enabledWhen':
    case 'fairWhen':
      return const ['type', 'field', 'when', 'reason'];
    case 'disables':
      if (rule.containsKey('source')) {
        return const ['type', 'source', 'targets', 'reason'];
      }
      return const ['type', 'when', 'targets', 'reason'];
    case 'oneOf':
    case 'eitherOf':
      return const ['type', 'group', 'branches'];
    case 'anyOf':
      return const ['type', 'rules'];
    case 'check':
      return [
        'type',
        'field',
        'reason',
        ..._validatorSpecMembers(rule['op']),
      ];
    default:
      throw UmpireSchemaException('Unknown rule type "${rule['type']}"');
  }
}

void _validateRequiresRule(
  Map<String, dynamic> rule,
  Set<String> fieldNames,
  Map<String, String> conditionTypes,
) {
  _assertField(rule['field'], fieldNames, 'Rule "requires"');

  if (rule.containsKey('dependency')) {
    _assertField(rule['dependency'], fieldNames, 'Rule "requires"');
    return;
  }

  if (rule.containsKey('dependencies')) {
    final dependencies = _array(rule, 'dependencies', 'Rule "requires"');
    if (dependencies.isEmpty) {
      throw UmpireSchemaException(
        '"requires" rules with dependencies must include at least one entry',
      );
    }
    for (final dependency in dependencies) {
      if (dependency is String) {
        _assertField(dependency, fieldNames, 'Rule "requires"');
      } else {
        _validateExprRoot(dependency, fieldNames, conditionTypes);
      }
    }
    return;
  }

  _validateExprRoot(rule['when'], fieldNames, conditionTypes);
}

void _validateDisablesRule(
  Map<String, dynamic> rule,
  Set<String> fieldNames,
  Map<String, String> conditionTypes,
) {
  final targets = _array(rule, 'targets', 'Rule "disables"');
  for (final target in targets) {
    _assertField(target, fieldNames, 'Rule "disables"');
  }

  if (rule.containsKey('source')) {
    _assertField(rule['source'], fieldNames, 'Rule "disables"');
    return;
  }

  _validateExprRoot(rule['when'], fieldNames, conditionTypes);
}

void _validateOneOfBranches(
  Map<String, dynamic> rule,
  Set<String> fieldNames,
) {
  final branches = _record(rule, 'branches', 'Rule "oneOf"');
  final names = branches.keys.toList();
  if (names.isEmpty) {
    throw UmpireSchemaException(
      'oneOf("${rule['group']}") must include at least one branch',
    );
  }
  for (final name in names) {
    final branchFields = _asList(
      branches[name],
      'Rule "oneOf" branch "$name"',
    );
    if (branchFields.isEmpty) {
      throw UmpireSchemaException(
        'oneOf("${rule['group']}") branch "$name" must not be empty',
      );
    }
    for (final field in branchFields) {
      _assertField(field, fieldNames, 'Rule "oneOf"');
    }
  }
}

List<String> _validatorSpecMembers(dynamic op) {
  return _validatorSpecMemberSets[op] ?? const ['op'];
}

void _validateValidatorDef(
  String field,
  dynamic definition,
  Set<String> fieldNames,
) {
  if (!fieldNames.contains(field)) {
    throw UmpireSchemaException(
      'Validator references unknown field "$field" (validator)',
    );
  }

  final record = _asRecord(definition, 'validator for field "$field"');
  _validateValidatorSpec(record, const ['error'], context: 'Validator spec');

  if (record.containsKey('error') && record['error'] is! String) {
    throw UmpireSchemaException(
      'Validator for field "$field" must use a string error when provided',
    );
  }
}

void _validateValidatorSpec(
  Map<String, dynamic> spec,
  List<String> additionalMembers, {
  String context = 'Validator spec',
}) {
  final op = spec['op'];
  _assertKnownMembers(
    spec,
    [..._validatorSpecMembers(op), ...additionalMembers],
    context,
  );

  if (op is! String) {
    throw UmpireSchemaException('$context must include a string "op"');
  }

  try {
    parseCheckOp(op, spec);
  } on FormatException catch (e) {
    throw UmpireSchemaException('Invalid regex pattern: ${e.message}');
  }
}

void _validateExcludedRule(dynamic rule) {
  final record = _asRecord(rule, 'Excluded rule');
  _assertKnownMembers(
    record,
    const ['type', 'field', 'description', 'key', 'signature'],
    'Excluded rule',
  );

  final type = record['type'];
  if (type is! String || type.isEmpty) {
    throw UmpireSchemaException(
      'Excluded rules must include a non-empty string type',
    );
  }
  final description = record['description'];
  if (description is! String || description.isEmpty) {
    throw UmpireSchemaException(
      'Excluded rules must include a non-empty string description',
    );
  }
  for (final member in const ['field', 'key', 'signature']) {
    if (record.containsKey(member) && record[member] is! String) {
      throw UmpireSchemaException(
        'Excluded rule $member must be a string when provided',
      );
    }
  }
}

void _validateExpression(
  dynamic expression,
  Set<String> fieldNames,
  Map<String, String> conditionTypes,
) {
  final record = _asRecord(expression, 'Expression');
  final op = record['op'];
  if (op is! String) {
    throw UmpireSchemaException('Expression must include a string "op"');
  }

  switch (op) {
    case 'eq':
    case 'neq':
      _assertKnownMembers(record, const ['op', 'field', 'value'], 'Expression');
      _assertExprField(record['field'], fieldNames, op);
      if (!_isJsonPrimitive(record['value'])) {
        throw UmpireSchemaException(
          'Expression "$op" value must be a JSON primitive',
        );
      }
    case 'gt':
    case 'gte':
    case 'lt':
    case 'lte':
      _assertKnownMembers(record, const ['op', 'field', 'value'], 'Expression');
      _assertExprField(record['field'], fieldNames, op);
      if (record['value'] is! num) {
        throw UmpireSchemaException(
          'Expression "$op" value must be a number',
        );
      }
    case 'present':
    case 'absent':
    case 'truthy':
    case 'falsy':
      _assertKnownMembers(record, const ['op', 'field'], 'Expression');
      _assertExprField(record['field'], fieldNames, op);
    case 'in':
    case 'notIn':
      _assertKnownMembers(
        record,
        const ['op', 'field', 'values'],
        'Expression',
      );
      _assertExprField(record['field'], fieldNames, op);
      _assertPrimitiveList(record['values'], 'Expression "$op" values');
    case 'cond':
      _assertKnownMembers(record, const ['op', 'condition'], 'Expression');
      _assertCondition(record, 'cond');
    case 'condEq':
      _assertKnownMembers(
        record,
        const ['op', 'condition', 'value'],
        'Expression',
      );
      _assertCondition(record, 'condEq');
      if (!_isJsonPrimitive(record['value'])) {
        throw UmpireSchemaException(
          'Expression "condEq" value must be a JSON primitive',
        );
      }
    case 'condIn':
      _assertKnownMembers(
        record,
        const ['op', 'condition', 'values'],
        'Expression',
      );
      _assertCondition(record, 'condIn');
      _assertPrimitiveList(record['values'], 'Expression "condIn" values');
    case 'fieldInCond':
      _assertKnownMembers(
        record,
        const ['op', 'field', 'condition'],
        'Expression',
      );
      _assertExprField(record['field'], fieldNames, 'fieldInCond');
      final condition = record['condition'];
      final conditionType =
          condition is String ? conditionTypes[condition] : null;
      if (conditionType == null || !conditionType.endsWith('[]')) {
        throw UmpireSchemaException(
          '"fieldInCond" requires an array condition; '
          '"$condition" is not declared as one',
        );
      }
    case 'and':
    case 'or':
      _assertKnownMembers(record, const ['op', 'exprs'], 'Expression');
      final exprs = _array(record, 'exprs', 'Expression "$op"');
      for (final entry in exprs) {
        _validateExpression(entry, fieldNames, conditionTypes);
      }
    case 'not':
      _assertKnownMembers(record, const ['op', 'expr'], 'Expression');
      _validateExpression(record['expr'], fieldNames, conditionTypes);
    case 'check':
      _assertKnownMembers(
        record,
        const ['op', 'field', 'check'],
        'Expression',
      );
      _assertExprField(record['field'], fieldNames, 'check');
      _validateValidatorSpec(
        _asRecord(record['check'], 'Validator spec'),
        const [],
      );
    case 'contains':
      _assertKnownMembers(
        record,
        const ['op', 'field', 'value'],
        'Expression',
      );
      _assertExprField(record['field'], fieldNames, 'contains');
    default:
      throw UmpireSchemaException('Unknown expression op "$op"');
  }
}

/// Validates the closed shape of [expression] and its subtree, then compiles
/// it once so field references and regex patterns are checked eagerly.
void _validateExprRoot(
  dynamic expression,
  Set<String> fieldNames,
  Map<String, String> conditionTypes,
) {
  _validateExpression(expression, fieldNames, conditionTypes);
  try {
    compileExpr(expression as Map<String, dynamic>, fieldNames: fieldNames);
  } on ArgumentError catch (e) {
    throw UmpireSchemaException(e.message.toString());
  }
}

/// Conditions may be supplied at runtime, so only their shape is checked here.
void _assertCondition(Map<String, dynamic> expression, String op) {
  if (expression['condition'] is! String) {
    throw UmpireSchemaException(
      'Expression "$op" condition must be a string',
    );
  }
}

void _assertField(dynamic field, Set<String> fieldNames, String context) {
  if (field is! String) {
    throw UmpireSchemaException('$context must reference a field by name');
  }
  if (!fieldNames.contains(field)) {
    throw UmpireSchemaException(
      '$context references unknown field "$field"',
    );
  }
}

void _assertExprField(dynamic field, Set<String> fieldNames, String op) {
  if (field is! String) {
    throw UmpireSchemaException('Expression "$op" field must be a string');
  }
  if (!fieldNames.contains(field)) {
    throw UmpireSchemaException('Unknown field "$field" in "$op" expression');
  }
}

void _assertPrimitiveList(dynamic values, String context) {
  if (values is! List || !values.every(_isJsonPrimitive)) {
    throw UmpireSchemaException(
      '$context must be an array of JSON primitives',
    );
  }
}

void _assertKnownMembers(
  Map<String, dynamic> value,
  List<String> allowed,
  String context,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw UmpireSchemaException(
        '$context has unknown member "$key"; '
        'expected ${allowed.join(', ')}',
      );
    }
  }
}

void _assertString(dynamic value, String context) {
  if (value is! String) {
    throw UmpireSchemaException('$context must be a string');
  }
}

bool _isJsonPrimitive(dynamic value) =>
    value == null || value is String || value is num || value is bool;

Map<String, dynamic> _asRecord(dynamic value, String context) {
  if (value is! Map<String, dynamic>) {
    throw UmpireSchemaException('$context must be an object');
  }
  return value;
}

List<dynamic> _asList(dynamic value, String context) {
  if (value is! List) {
    throw UmpireSchemaException('$context must be an array');
  }
  return value;
}

Map<String, dynamic> _record(
  Map<String, dynamic> parent,
  String key,
  String context,
) =>
    _asRecord(parent[key], '$context "$key"');

Map<String, dynamic>? _optionalRecord(
  Map<String, dynamic> parent,
  String key,
  String context,
) {
  if (!parent.containsKey(key) || parent[key] == null) return null;
  return _asRecord(parent[key], '$context "$key"');
}

List<dynamic> _array(
  Map<String, dynamic> parent,
  String key,
  String context,
) =>
    _asList(parent[key], '$context "$key"');

List<dynamic>? _optionalArray(
  Map<String, dynamic> parent,
  String key,
  String context,
) {
  if (!parent.containsKey(key) || parent[key] == null) return null;
  return _asList(parent[key], '$context "$key"');
}
