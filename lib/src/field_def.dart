/// Defines a field's structure and emptiness semantics.
class FieldDef {
  final bool required;
  final dynamic defaultValue;
  final IsEmptyStrategy isEmpty;

  const FieldDef({
    this.required = false,
    this.defaultValue,
    this.isEmpty = IsEmptyStrategy.present,
  });
}

/// Strategy for determining when a field value is "empty".
enum IsEmptyStrategy {
  /// Value is null or absent — the default.
  present,

  /// Value is not a string, or is an empty string.
  string,

  /// Value is not a number, or is NaN.
  number,

  /// Value is not a boolean.
  boolean,

  /// Value is not a list, or is an empty list.
  array,
}
