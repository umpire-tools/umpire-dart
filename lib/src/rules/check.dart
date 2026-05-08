import 'rule.dart';

/// Creates a predicate that validates [field] against a [validator].
///
/// Returns a [Predicate] suitable for use with [enabledWhen], [requires], etc.
Predicate check(String field, bool Function(dynamic value) validator) {
  return (values, conditions) {
    final value = values[field];
    if (value == null) return false;
    return validator(value);
  };
}
