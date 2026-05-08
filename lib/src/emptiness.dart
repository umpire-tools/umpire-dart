import 'field_def.dart';

bool isEmptyPresent(dynamic value) => value == null;

bool isEmptyString(dynamic value) => value is! String || value.isEmpty;

bool isEmptyNumber(dynamic value) => value is! num || value.isNaN;

bool isEmptyBoolean(dynamic value) => value is! bool;

bool isEmptyArray(dynamic value) => value is! List || value.isEmpty;

bool isEmptyObject(dynamic value) {
  if (value is! Map) return true;
  return value.isEmpty;
}

bool checkIsEmpty(IsEmptyStrategy strategy, dynamic value) {
  switch (strategy) {
    case IsEmptyStrategy.string:
      return isEmptyString(value);
    case IsEmptyStrategy.number:
      return isEmptyNumber(value);
    case IsEmptyStrategy.boolean:
      return isEmptyBoolean(value);
    case IsEmptyStrategy.array:
      return isEmptyArray(value);
    case IsEmptyStrategy.object:
      return isEmptyObject(value);
    case IsEmptyStrategy.present:
      return isEmptyPresent(value);
  }
}
