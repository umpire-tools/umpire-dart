import '../rules/rule.dart';
import 'check_op.dart';
import 'errors.dart';

const _maxExprDepth = 50;

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  return true;
}

/// Compiles a `check` expression's validator spec through [parseCheckOp], so a
/// check reaches the same verdict whether it arrives as a `check` rule or a
/// `check` expression.
///
/// [parseCheckOp] reports schema-shaped failures; they surface here as
/// [ArgumentError] like every other malformed expression.
bool Function(dynamic) _compileCheck(Map<String, dynamic> check) {
  final op = check['op'];
  try {
    return parseCheckOp(op is String ? op : null, check).validate;
  } on UmpireSchemaException catch (e) {
    throw ArgumentError(e.message);
  } on FormatException catch (e) {
    throw ArgumentError(
      'Invalid regex pattern in "matches" check: '
      '${check['pattern']} — ${e.message}',
    );
  }
}

String _validateField(Map<String, dynamic> expr, Set<String> fieldNames) {
  final field = expr['field'] as String?;
  if (field == null || !fieldNames.contains(field)) {
    throw ArgumentError('Unknown field "$field" in expression');
  }
  return field;
}

Predicate compileExpr(
  Map<String, dynamic> expr, {
  required Set<String> fieldNames,
  int depth = 0,
}) {
  final op = expr['op'] as String?;
  if (op == null) throw ArgumentError('Expression missing "op" field');
  if (depth > _maxExprDepth) {
    throw ArgumentError('Expression nesting too deep (max $_maxExprDepth)');
  }

  switch (op) {
    case 'cond':
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('cond expression missing "condition" field');
      }
      return (values, conditions) {
        if (!conditions.containsKey(condition)) {
          throw ArgumentError('Missing runtime condition "$condition"');
        }
        return conditions[condition] == true;
      };

    case 'condEq':
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('condEq expression missing "condition" field');
      }
      final value = expr['value'];
      return (values, conditions) {
        if (!conditions.containsKey(condition)) {
          throw ArgumentError('Missing runtime condition "$condition"');
        }
        return conditions[condition] == value;
      };

    case 'condIn':
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('condIn expression missing "condition" field');
      }
      final values = expr['values'] as List?;
      if (values == null) {
        throw ArgumentError('condIn expression missing "values" field');
      }
      return (vs, conditions) {
        if (!conditions.containsKey(condition)) {
          throw ArgumentError('Missing runtime condition "$condition"');
        }
        return values.contains(conditions[condition]);
      };

    case 'fieldInCond':
      final field = _validateField(expr, fieldNames);
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('fieldInCond expression missing "condition" field');
      }
      return (values, conditions) {
        if (!conditions.containsKey(condition)) {
          throw ArgumentError('Missing runtime condition "$condition"');
        }
        final c = conditions[condition];
        return c is List && c.contains(values[field]);
      };

    case 'eq':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'];
      return (values, conditions) => values[field] == value;

    case 'neq':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'];
      return (values, conditions) => values[field] != value;

    case 'gt':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'] as num?;
      if (value == null) throw ArgumentError('gt expression missing "value"');
      return (values, conditions) {
        final v = values[field];
        return v is num && v > value;
      };

    case 'gte':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'] as num?;
      if (value == null) throw ArgumentError('gte expression missing "value"');
      return (values, conditions) {
        final v = values[field];
        return v is num && v >= value;
      };

    case 'lt':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'] as num?;
      if (value == null) throw ArgumentError('lt expression missing "value"');
      return (values, conditions) {
        final v = values[field];
        return v is num && v < value;
      };

    case 'lte':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'] as num?;
      if (value == null) throw ArgumentError('lte expression missing "value"');
      return (values, conditions) {
        final v = values[field];
        return v is num && v <= value;
      };

    case 'truthy':
      final field = _validateField(expr, fieldNames);
      return (values, conditions) => _truthy(values[field]);

    case 'falsy':
      final field = _validateField(expr, fieldNames);
      return (values, conditions) => !_truthy(values[field]);

    case 'and':
      final exprs = expr['exprs'] as List?;
      if (exprs == null || exprs.isEmpty) {
        throw ArgumentError('and expression requires non-empty "exprs"');
      }
      final predicates = exprs
          .map((e) => compileExpr(e as Map<String, dynamic>,
              fieldNames: fieldNames, depth: depth + 1))
          .toList();
      return (values, conditions) =>
          predicates.every((p) => p(values, conditions));

    case 'or':
      final exprs = expr['exprs'] as List?;
      if (exprs == null || exprs.isEmpty) {
        throw ArgumentError('or expression requires non-empty "exprs"');
      }
      final predicates = exprs
          .map((e) => compileExpr(e as Map<String, dynamic>,
              fieldNames: fieldNames, depth: depth + 1))
          .toList();
      return (values, conditions) =>
          predicates.any((p) => p(values, conditions));

    case 'not':
      final subExpr = expr['expr'] as Map<String, dynamic>?;
      if (subExpr == null) {
        throw ArgumentError('not expression missing "expr" field');
      }
      final predicate =
          compileExpr(subExpr, fieldNames: fieldNames, depth: depth + 1);
      return (values, conditions) => !predicate(values, conditions);

    case 'present':
      final field = _validateField(expr, fieldNames);
      return (values, conditions) =>
          values.containsKey(field) && values[field] != null;

    case 'absent':
      final field = _validateField(expr, fieldNames);
      return (values, conditions) =>
          !values.containsKey(field) || values[field] == null;

    case 'in':
      final field = _validateField(expr, fieldNames);
      final valuesList = expr['values'] as List?;
      if (valuesList == null) {
        throw ArgumentError('in expression missing "values" field');
      }
      return (vs, conditions) => valuesList.contains(vs[field]);

    case 'notIn':
      final field = _validateField(expr, fieldNames);
      final valuesList = expr['values'] as List?;
      if (valuesList == null) {
        throw ArgumentError('notIn expression missing "values" field');
      }
      return (vs, conditions) => !valuesList.contains(vs[field]);

    case 'contains':
      final field = _validateField(expr, fieldNames);
      final value = expr['value'];
      return (values, conditions) {
        final v = values[field];
        return v is List && v.contains(value);
      };

    case 'check':
      final field = _validateField(expr, fieldNames);
      final check = expr['check'] as Map<String, dynamic>?;
      if (check == null) {
        throw ArgumentError('check expression missing "check" field');
      }
      final checkFn = _compileCheck(check);
      return (values, conditions) {
        final v = values[field];
        if (v == null) return false;
        return checkFn(v);
      };

    default:
      throw ArgumentError('Unknown expression op: "$op"');
  }
}
