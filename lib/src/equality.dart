/// Left-dispatched equality check for change detection.
///
/// Honors identity first, then delegates to `.equals()` on [a] if available.
bool isEqual(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is! Equatable) return false;
  return a.equals(b);
}

/// Interface for objects that support custom equality via `.equals()`.
abstract class Equatable {
  bool equals(Object? other);
}
