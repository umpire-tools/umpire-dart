import 'emptiness.dart';
import 'field_def.dart';

/// Returns true if a field value is "satisfied" (not empty).
bool isSatisfied(dynamic value, FieldDef? fieldDef) {
  if (fieldDef != null) {
    return !checkIsEmpty(fieldDef.isEmpty, value);
  }

  return !isEmptyPresent(value);
}
