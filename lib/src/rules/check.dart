import '../check_ops.dart';
import 'rule.dart';

/// Creates a predicate that validates [field] against a [validator].
///
/// The [validator] can be a plain function `(value) => bool`, or a [CheckOp]
/// from [checkOps] (e.g. `checkOps.email()`, `checkOps.minLength(8)`).
///
/// Returns a [Predicate] suitable for use with [enabledWhen], [requires], etc.
///
/// ```dart
/// // Plain function
/// check('username', (v) => v.toString().length >= 3)
///
/// // Named check op
/// check('email', checkOps.email(reason: 'Must be valid email'))
/// ```
Predicate check(String field, dynamic validator) {
  if (validator is CheckOp) {
    final op = validator;
    return (values, conditions) {
      final value = values[field];
      if (value == null) return false;
      return op.validate(value);
    };
  }

  if (validator is bool Function(dynamic)) {
    return (values, conditions) {
      final value = values[field];
      if (value == null) return false;
      return validator(value);
    };
  }

  throw ArgumentError('validator must be a bool Function(dynamic) or CheckOp');
}
