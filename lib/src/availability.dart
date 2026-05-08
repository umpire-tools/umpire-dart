/// The result of evaluating a single field.
class FieldAvailability {
  final bool enabled;
  final bool required;
  final bool fair;
  final bool satisfied;
  final String? reason;
  final List<String> reasons;

  const FieldAvailability({
    required this.enabled,
    required this.required,
    required this.fair,
    required this.satisfied,
    this.reason,
    this.reasons = const [],
  });
}

/// Maps field names to their availability status.
typedef AvailabilityMap = Map<String, FieldAvailability>;

/// A recommended value correction when form state transitions.
class Foul {
  final String field;
  final String reason;
  final dynamic suggestedValue;

  const Foul({
    required this.field,
    required this.reason,
    this.suggestedValue,
  });
}
