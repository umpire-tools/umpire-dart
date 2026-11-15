import '../check_ops.dart';
import 'errors.dart';

/// The closed validator op set with the parameters each op reads.
///
/// The schema walk takes its allowed members from here and [parseCheckOp] takes
/// its parameter names from here, so an op cannot declare parameters in one
/// place and ignore them in the other.
const _checkOpParams = <String, List<String>>{
  'email': [],
  'url': [],
  'matches': ['pattern'],
  'minLength': ['value'],
  'maxLength': ['value'],
  'min': ['value'],
  'max': ['value'],
  'range': ['min', 'max'],
  'integer': [],
};

/// The members a validator spec for [op] may declare, `op` included.
///
/// Returns `const ['op']` for a missing or unknown op, leaving the rejection to
/// the caller's own op check.
List<String> checkOpMembers(String? op) => [
      'op',
      ...?_checkOpParams[op],
    ];

/// Parses a validator spec into a [CheckOp].
///
/// This is the single authority for the closed validator op set and each op's
/// parameter rules, shared by the schema walk, the JSON parser, and `build()`.
/// [checkOpMembers] carries the same op set for the schema walk's member check.
///
/// Throws [UmpireSchemaException] for an unknown op or a missing or mistyped
/// parameter. `matches` builds its [RegExp] here, so an invalid pattern
/// surfaces as a [FormatException].
CheckOp parseCheckOp(String? op, Map<String, dynamic> params) {
  if (op == null) {
    throw UmpireSchemaException('Check rule missing "op" field');
  }
  if (!_checkOpParams.containsKey(op)) {
    throw UmpireSchemaException('Unknown check op: "$op"');
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
  }

  // Reachable only if _checkOpParams gains an op without a parser above.
  throw StateError('Check op "$op" is declared without a parser');
}
