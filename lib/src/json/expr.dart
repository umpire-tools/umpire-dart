import '../rules/rule.dart';

const _maxExprDepth = 50;

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  return true;
}

bool Function(dynamic) _compileCheck(Map<String, dynamic> check) {
  final op = check['op'] as String?;
  switch (op) {
    case 'email':
      return (v) {
        if (v is! String || v.isEmpty) return false;
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
      };
    case 'url':
      return (v) {
        if (v is! String || v.isEmpty) return false;
        final uri = Uri.tryParse(v);
        return uri != null && uri.hasScheme && uri.hasAuthority;
      };
    case 'matches':
      final pattern = check['pattern'] as String?;
      if (pattern == null) {
        throw ArgumentError('Check "matches" requires a "pattern" parameter');
      }
      try {
        final regex = RegExp(pattern);
        return (v) {
          if (v is! String) return false;
          return regex.hasMatch(v);
        };
      } on FormatException catch (e) {
        throw ArgumentError(
            'Invalid regex pattern in "matches" check: $pattern — ${e.message}');
      }
    case 'minLength':
      final min = check['min'] as num?;
      if (min == null) {
        throw ArgumentError('Check "minLength" requires a "min" parameter');
      }
      return (v) {
        if (v is! String) return false;
        return v.length >= min;
      };
    case 'maxLength':
      final max = check['max'] as num?;
      if (max == null) {
        throw ArgumentError('Check "maxLength" requires a "max" parameter');
      }
      return (v) {
        if (v is! String) return false;
        return v.length <= max;
      };
    case 'min':
      final minValue = check['min'] as num?;
      if (minValue == null) {
        throw ArgumentError('Check "min" requires a "min" parameter');
      }
      return (v) {
        if (v is! num) return false;
        return v >= minValue;
      };
    case 'max':
      final maxValue = check['max'] as num?;
      if (maxValue == null) {
        throw ArgumentError('Check "max" requires a "max" parameter');
      }
      return (v) {
        if (v is! num) return false;
        return v <= maxValue;
      };
    case 'range':
      final minValue = check['min'] as num?;
      final maxValue = check['max'] as num?;
      if (minValue == null || maxValue == null) {
        throw ArgumentError('Check "range" requires "min" and "max" parameters');
      }
      return (v) {
        if (v is! num) return false;
        return v >= minValue && v <= maxValue;
      };
    case 'integer':
      return (v) {
        if (v is! num) return false;
        return v == v.roundToDouble();
      };
    default:
      throw ArgumentError('Unknown check op: "$op"');
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
      return (values, conditions) => conditions[condition] == true;

    case 'condEq':
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('condEq expression missing "condition" field');
      }
      final value = expr['value'];
      return (values, conditions) => conditions[condition] == value;

    case 'condIn':
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('condIn expression missing "condition" field');
      }
      final values = expr['values'] as List?;
      if (values == null) {
        throw ArgumentError('condIn expression missing "values" field');
      }
      return (vs, conditions) => values.contains(conditions[condition]);

    case 'fieldInCond':
      final field = _validateField(expr, fieldNames);
      final condition = expr['condition'] as String?;
      if (condition == null) {
        throw ArgumentError('fieldInCond expression missing "condition" field');
      }
      return (values, conditions) {
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
