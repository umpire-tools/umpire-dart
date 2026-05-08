import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

void main() {
  group('isSatisfied', () {
    test('null is not satisfied', () {
      expect(isSatisfied(null, null), isFalse);
    });

    test('non-null is satisfied with no fieldDef', () {
      expect(isSatisfied('hello', null), isTrue);
    });

    test('empty string is not satisfied when isEmpty is string', () {
      expect(
        isSatisfied('', FieldDef(isEmpty: IsEmptyStrategy.string)),
        isFalse,
      );
    });

    test('non-empty string is satisfied when isEmpty is string', () {
      expect(
        isSatisfied('hello', FieldDef(isEmpty: IsEmptyStrategy.string)),
        isTrue,
      );
    });

    test('default FieldDef uses present strategy', () {
      expect(isSatisfied(null, FieldDef()), isFalse);
      expect(isSatisfied('hello', FieldDef()), isTrue);
    });
  });
}
