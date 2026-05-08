/// A named validation check with metadata for introspection and JSON schema
/// compilation.
///
/// Used by [checkOps] factories and passed to [check] as a predicate.
class CheckOp {
  /// The check type name, e.g. `"email"`, `"minLength"`.
  final String name;

  /// Optional parameters for the check, e.g. `{"min": 8}`.
  final Map<String, dynamic>? params;

  /// The validation function.
  final bool Function(dynamic value) validate;

  const CheckOp({
    required this.name,
    this.params,
    required this.validate,
  });
}

/// Factory methods for common validation checks.
///
/// Each method returns a [CheckOp] suitable for use with [check].
///
/// ```dart
/// check('email', checkOps.email(reason: 'Must be a valid email'));
/// check('password', checkOps.minLength(8));
/// ```
abstract class checkOps {
  checkOps._(); // prevent instantiation

  /// Validates that the value is a non-empty email address.
  static CheckOp email({String? reason}) {
    return CheckOp(
      name: 'email',
      validate: (value) {
        if (value is! String || value.isEmpty) return false;
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
      },
    );
  }

  /// Validates that the value is a URL.
  static CheckOp url({String? reason}) {
    return CheckOp(
      name: 'url',
      validate: (value) {
        if (value is! String || value.isEmpty) return false;
        final uri = Uri.tryParse(value);
        return uri != null && uri.hasScheme && uri.hasAuthority;
      },
    );
  }

  /// Validates that the value matches [pattern].
  static CheckOp matches(RegExp pattern, {String? reason}) {
    return CheckOp(
      name: 'matches',
      params: {'pattern': pattern.pattern},
      validate: (value) {
        if (value is! String) return false;
        return pattern.hasMatch(value);
      },
    );
  }

  /// Validates that the string value has at least [min] characters.
  static CheckOp minLength(int min, {String? reason}) {
    return CheckOp(
      name: 'minLength',
      params: {'min': min},
      validate: (value) {
        if (value is! String) return false;
        return value.length >= min;
      },
    );
  }

  /// Validates that the string value has at most [max] characters.
  static CheckOp maxLength(int max, {String? reason}) {
    return CheckOp(
      name: 'maxLength',
      params: {'max': max},
      validate: (value) {
        if (value is! String) return false;
        return value.length <= max;
      },
    );
  }

  /// Validates that the numeric value is at least [min].
  static CheckOp min(num minValue, {String? reason}) {
    return CheckOp(
      name: 'min',
      params: {'min': minValue},
      validate: (value) {
        if (value is! num) return false;
        return value >= minValue;
      },
    );
  }

  /// Validates that the numeric value is at most [max].
  static CheckOp max(num maxValue, {String? reason}) {
    return CheckOp(
      name: 'max',
      params: {'max': maxValue},
      validate: (value) {
        if (value is! num) return false;
        return value <= maxValue;
      },
    );
  }

  /// Validates that the numeric value is within [[minValue], [maxValue]] inclusive.
  static CheckOp range(num minValue, num maxValue, {String? reason}) {
    return CheckOp(
      name: 'range',
      params: {'min': minValue, 'max': maxValue},
      validate: (value) {
        if (value is! num) return false;
        return value >= minValue && value <= maxValue;
      },
    );
  }

  /// Validates that the number is an integer (no fractional part).
  static CheckOp integer({String? reason}) {
    return CheckOp(
      name: 'integer',
      validate: (value) {
        if (value is! num) return false;
        return value == value.roundToDouble();
      },
    );
  }
}
