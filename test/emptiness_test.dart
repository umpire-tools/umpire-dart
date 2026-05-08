import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

void main() {
  group('isEmptyPresent', () {
    test('null is empty', () => expect(isEmptyPresent(null), isTrue));
    test('string is not empty', () => expect(isEmptyPresent('hello'), isFalse));
    test('0 is not empty', () => expect(isEmptyPresent(0), isFalse));
    test('false is not empty', () => expect(isEmptyPresent(false), isFalse));
    test('empty list is not empty', () => expect(isEmptyPresent([]), isFalse));
  });

  group('isEmptyString', () {
    test('empty string is empty', () => expect(isEmptyString(''), isTrue));
    test('non-string is empty', () => expect(isEmptyString(5), isTrue));
    test('non-empty string is not empty', () => expect(isEmptyString('hello'), isFalse));
  });

  group('isEmptyNumber', () {
    test('NaN is empty', () => expect(isEmptyNumber(double.nan), isTrue));
    test('non-number is empty', () => expect(isEmptyNumber('5'), isTrue));
    test('number is not empty', () => expect(isEmptyNumber(5), isFalse));
    test('zero is not empty', () => expect(isEmptyNumber(0), isFalse));
  });

  group('isEmptyBoolean', () {
    test('non-boolean is empty', () => expect(isEmptyBoolean('true'), isTrue));
    test('true is not empty', () => expect(isEmptyBoolean(true), isFalse));
    test('false is not empty', () => expect(isEmptyBoolean(false), isFalse));
  });

  group('isEmptyArray', () {
    test('empty list is empty', () => expect(isEmptyArray([]), isTrue));
    test('non-list is empty', () => expect(isEmptyArray('hello'), isTrue));
    test('non-empty list is not empty', () => expect(isEmptyArray([1, 2]), isFalse));
  });

  group('checkIsEmpty', () {
    test('present: null is empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.present, null), isTrue);
    });
    test('present: value is not empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.present, 'hi'), isFalse);
    });
    test('string: empty string is empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.string, ''), isTrue);
    });
    test('string: valid string is not empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.string, 'hello'), isFalse);
    });
    test('number: NaN is empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.number, double.nan), isTrue);
    });
    test('array: empty list is empty', () {
      expect(checkIsEmpty(IsEmptyStrategy.array, []), isTrue);
    });
  });
}
