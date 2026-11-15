import '../check_ops.dart';
import 'errors.dart';

/// Parses a validator spec into a [CheckOp].
///
/// This is the single authority for the closed validator op set and each op's
/// parameter rules, shared by the schema walk, the JSON parser, and `build()`.
///
/// Throws [UmpireSchemaException] for an unknown op or a missing or mistyped
/// parameter. `matches` builds its [RegExp] here, so an invalid pattern
/// surfaces as a [FormatException].
CheckOp parseCheckOp(String? op, Map<String, dynamic> params) {
  if (op == null) {
    throw UmpireSchemaException('Check rule missing "op" field');
  }

  switch (op) {
    case 'email':
      return checkOps.email();
    case 'url':
      return checkOps.url();
    case 'matches':
      final pattern = params['pattern'];
      if (pattern is! String) {
        throw UmpireSchemaException(
          'Check "matches" requires a string "pattern"',
        );
      }
      return checkOps.matches(RegExp(pattern));
    case 'minLength':
      final min = params['value'];
      if (min is! num) {
        throw UmpireSchemaException(
          'Check "minLength" requires a numeric "value"',
        );
      }
      return checkOps.minLength(min.toInt());
    case 'maxLength':
      final max = params['value'];
      if (max is! num) {
        throw UmpireSchemaException(
          'Check "maxLength" requires a numeric "value"',
        );
      }
      return checkOps.maxLength(max.toInt());
    case 'min':
      final min = params['value'];
      if (min is! num) {
        throw UmpireSchemaException(
          'Check "min" requires a numeric "value"',
        );
      }
      return checkOps.min(min);
    case 'max':
      final max = params['value'];
      if (max is! num) {
        throw UmpireSchemaException(
          'Check "max" requires a numeric "value"',
        );
      }
      return checkOps.max(max);
    case 'range':
      final min = params['min'];
      final max = params['max'];
      if (min is! num || max is! num) {
        throw UmpireSchemaException(
          'Check "range" requires numeric "min" and "max"',
        );
      }
      return checkOps.range(min, max);
    case 'integer':
      return checkOps.integer();
    default:
      throw UmpireSchemaException('Unknown check op: "$op"');
  }
}
