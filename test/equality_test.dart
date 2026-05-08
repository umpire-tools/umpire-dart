import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

class _Eq implements Equatable {
  final int value;
  const _Eq(this.value);
  @override
  bool equals(Object? other) => other is _Eq && other.value == value;
}

void main() {
  group('isEqual', () {
    test('identical primitives are equal', () {
      expect(isEqual('hello', 'hello'), isTrue);
      expect(isEqual(42, 42), isTrue);
    });

    test('different primitives are not equal', () {
      expect(isEqual('hello', 'world'), isFalse);
      expect(isEqual(42, 43), isFalse);
    });

    test('null and non-null are not equal', () {
      expect(isEqual(null, 'hello'), isFalse);
      expect(isEqual(null, null), isTrue);
    });

    test('Equatable objects delegate to .equals()', () {
      expect(isEqual(_Eq(1), _Eq(1)), isTrue);
      expect(isEqual(_Eq(1), _Eq(2)), isFalse);
    });
  });
}
