/// A named validation check with metadata for introspection and JSON schema
/// compilation.
///
/// Used by [checkOps] factories and passed to [check] as a predicate.
class CheckOp {
  final String name;
  final Map<String, dynamic>? params;
  final bool Function(dynamic value) validate;
  final String? reason;

  const CheckOp({
    required this.name,
    this.params,
    required this.validate,
    this.reason,
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
      reason: reason ?? 'Must be a valid email address',
      validate: (value) {
        if (value is! String || value.isEmpty) return false;
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
      },
    );
  }

  static CheckOp url({String? reason}) {
    return CheckOp(
      name: 'url',
      reason: reason ?? 'Must be a valid URL',
      validate: (value) {
        if (value is! String || value.isEmpty) return false;
        final uri = Uri.tryParse(value);
        return uri != null && uri.hasScheme && uri.hasAuthority;
      },
    );
  }

  static CheckOp matches(RegExp pattern, {String? reason}) {
    return CheckOp(
      name: 'matches',
      params: {'pattern': pattern.pattern},
      reason: reason ?? 'Must match the required format',
      validate: (value) {
        if (value is! String) return false;
        return pattern.hasMatch(value);
      },
    );
  }

  static CheckOp minLength(int min, {String? reason}) {
    return CheckOp(
      name: 'minLength',
      params: {'min': min},
      reason: reason ?? 'Must be at least $min characters',
      validate: (value) {
        if (value is String) return value.length >= min;
        if (value is List) return value.length >= min;
        return false;
      },
    );
  }

  static CheckOp maxLength(int max, {String? reason}) {
    return CheckOp(
      name: 'maxLength',
      params: {'max': max},
      reason: reason ?? 'Must be $max characters or fewer',
      validate: (value) {
        if (value is String) return value.length <= max;
        if (value is List) return value.length <= max;
        return false;
      },
    );
  }

  static CheckOp min(num minValue, {String? reason}) {
    return CheckOp(
      name: 'min',
      params: {'min': minValue},
      reason: reason ?? 'Must be at least $minValue',
      validate: (value) {
        if (value is! num) return false;
        return value >= minValue;
      },
    );
  }

  static CheckOp max(num maxValue, {String? reason}) {
    return CheckOp(
      name: 'max',
      params: {'max': maxValue},
      reason: reason ?? 'Must be $maxValue or less',
      validate: (value) {
        if (value is! num) return false;
        return value <= maxValue;
      },
    );
  }

  static CheckOp range(num minValue, num maxValue, {String? reason}) {
    return CheckOp(
      name: 'range',
      params: {'min': minValue, 'max': maxValue},
      reason: reason ?? 'Must be between $minValue and $maxValue',
      validate: (value) {
        if (value is! num) return false;
        return value >= minValue && value <= maxValue;
      },
    );
  }

  static CheckOp integer({String? reason}) {
    return CheckOp(
      name: 'integer',
      reason: reason ?? 'Must be a whole number',
      validate: (value) {
        if (value is! num) return false;
        return value == value.roundToDouble();
      },
    );
  }
}
