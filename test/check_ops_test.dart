import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

void main() {
  group('check() with plain function', () {
    test('returns true when validator passes', () {
      final pred = check('email', (v) => v.toString().contains('@'));
      expect(pred({'email': 'a@b.com'}, {}), isTrue);
    });

    test('returns false when validator fails', () {
      final pred = check('email', (v) => false);
      expect(pred({'email': 'a@b.com'}, {}), isFalse);
    });

    test('returns false when field value is null', () {
      final pred = check('email', (v) => true);
      expect(pred({'email': null}, {}), isFalse);
    });
  });

  group('check() with CheckOp', () {
    test('accepts CheckOp from checkOps', () {
      final pred = check('email', checkOps.email());
      expect(pred({'email': 'a@b.com'}, {}), isTrue);
      expect(pred({'email': 'invalid'}, {}), isFalse);
    });
  });

  group('checkOps.email', () {
    final op = checkOps.email();

    test('accepts valid email', () {
      expect(op.validate('user@example.com'), isTrue);
      expect(op.validate('a@b.co'), isTrue);
      expect(op.validate('test.user+tag@domain.org'), isTrue);
    });

    test('rejects invalid email', () {
      expect(op.validate(''), isFalse);
      expect(op.validate('notanemail'), isFalse);
      expect(op.validate('@missing-local.com'), isFalse);
      expect(op.validate('missing-domain@'), isFalse);
    });

    test('rejects non-string values', () {
      expect(op.validate(123), isFalse);
      expect(op.validate(null), isFalse);
    });
  });

  group('checkOps.url', () {
    final op = checkOps.url();

    test('accepts valid URLs', () {
      expect(op.validate('https://example.com'), isTrue);
      expect(op.validate('http://localhost:8080/path'), isTrue);
      expect(op.validate('ftp://files.example.com'), isTrue);
    });

    test('rejects invalid URLs', () {
      expect(op.validate(''), isFalse);
      expect(op.validate('not-a-url'), isFalse);
      expect(op.validate('example.com'), isFalse);
    });
  });

  group('checkOps.matches', () {
    final op = checkOps.matches(RegExp(r'^[a-z0-9_]+$'));

    test('accepts matching strings', () {
      expect(op.validate('hello_world'), isTrue);
      expect(op.validate('test123'), isTrue);
    });

    test('rejects non-matching strings', () {
      expect(op.validate('Hello World'), isFalse);
      expect(op.validate('test@123'), isFalse);
      expect(op.validate(''), isFalse);
    });

    test('rejects non-string values', () {
      expect(op.validate(123), isFalse);
    });

    test('stores pattern in params', () {
      expect(op.params?['pattern'], r'^[a-z0-9_]+$');
    });
  });

  group('checkOps.minLength', () {
    final op = checkOps.minLength(3);

    test('accepts strings at or above minimum', () {
      expect(op.validate('abc'), isTrue);
      expect(op.validate('abcd'), isTrue);
    });

    test('rejects strings below minimum', () {
      expect(op.validate('ab'), isFalse);
      expect(op.validate(''), isFalse);
    });

    test('rejects non-string values', () {
      expect(op.validate(123), isFalse);
    });

    test('stores min in params', () {
      expect(op.params?['min'], 3);
    });
  });

  group('checkOps.maxLength', () {
    final op = checkOps.maxLength(5);

    test('accepts strings at or below maximum', () {
      expect(op.validate('abc'), isTrue);
      expect(op.validate('abcde'), isTrue);
    });

    test('rejects strings above maximum', () {
      expect(op.validate('abcdef'), isFalse);
    });

    test('stores max in params', () {
      expect(op.params?['max'], 5);
    });
  });

  group('checkOps.min', () {
    final op = checkOps.min(10);

    test('accepts numbers at or above minimum', () {
      expect(op.validate(10), isTrue);
      expect(op.validate(15), isTrue);
      expect(op.validate(10.5), isTrue);
    });

    test('rejects numbers below minimum', () {
      expect(op.validate(9), isFalse);
      expect(op.validate(0), isFalse);
    });

    test('rejects non-numeric values', () {
      expect(op.validate('abc'), isFalse);
    });

    test('stores min in params', () {
      expect(op.params?['min'], 10);
    });
  });

  group('checkOps.max', () {
    final op = checkOps.max(100);

    test('accepts numbers at or below maximum', () {
      expect(op.validate(100), isTrue);
      expect(op.validate(50), isTrue);
    });

    test('rejects numbers above maximum', () {
      expect(op.validate(101), isFalse);
    });
  });

  group('checkOps.range', () {
    final op = checkOps.range(0, 100);

    test('accepts numbers within range', () {
      expect(op.validate(0), isTrue);
      expect(op.validate(50), isTrue);
      expect(op.validate(100), isTrue);
    });

    test('rejects numbers outside range', () {
      expect(op.validate(-1), isFalse);
      expect(op.validate(101), isFalse);
    });

    test('stores min and max in params', () {
      expect(op.params?['min'], 0);
      expect(op.params?['max'], 100);
    });
  });

  group('checkOps.integer', () {
    final op = checkOps.integer();

    test('accepts integer values', () {
      expect(op.validate(0), isTrue);
      expect(op.validate(42), isTrue);
      expect(op.validate(-7), isTrue);
      expect(op.validate(1.0), isTrue);
    });

    test('rejects non-integer values', () {
      expect(op.validate(3.14), isFalse);
      expect(op.validate(1.5), isFalse);
    });

    test('rejects non-numeric values', () {
      expect(op.validate('abc'), isFalse);
      expect(op.validate(null), isFalse);
    });
  });

  group('check() with checkOps used in umpire rules', () {
    test('enabledWhen with checkOps.email', () {
      final ump = umpire(
        fields: {'email': FieldDef(required: true)},
        rules: [
          enabledWhen(
            'email',
            predicate: check('email', checkOps.email()),
          ),
        ],
      );

      final valid = ump.check({'email': 'user@test.com'});
      expect(valid['email']!.enabled, isTrue);

      final invalid = ump.check({'email': 'bad-email'});
      expect(invalid['email']!.enabled, isFalse);
    });

    test('requires with checkOps.minLength', () {
      final ump = umpire(
        fields: {
          'username': FieldDef(required: true),
          'bio': FieldDef(required: false),
        },
        rules: [
          requires('bio',
            dependency: 'username',
          ),
        ],
      );

      final avail = ump.check({'username': 'alice', 'bio': 'hello'});
      expect(avail['bio']!.enabled, isTrue);
    });

    test('check() predicate used with fairWhen', () {
      final ump = umpire(
        fields: {'score': FieldDef(required: true)},
        rules: [
          fairWhen(
            'score',
            predicate: (val, v, c) => val >= 0,
          ),
        ],
      );

      expect(ump.check({'score': 10})['score']!.fair, isTrue);
      expect(ump.check({'score': -5})['score']!.fair, isFalse);
    });
  });
}
