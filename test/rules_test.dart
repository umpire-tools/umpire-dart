import 'package:test/test.dart';
import 'package:umpire/umpire.dart' hide anyOf;
import 'package:umpire/src/rules/any_of.dart' as umpire_rules;

void main() {
  group('disables rule', () {
    test('disables with when predicate (not just source satisfaction)', () {
      final ump = umpire(
        fields: {
          'mode': FieldDef(),
          'email': FieldDef(),
          'phone': FieldDef(),
        },
        rules: [
          disables('mode', ['email', 'phone'],
            when: (v, c) => v['mode'] == 'email-only',
            reason: 'Email-only mode disables phone',
          ),
        ],
      );

      final emailOnly = ump.check({'mode': 'email-only'});
      expect(emailOnly['email']!.enabled, isFalse);
      expect(emailOnly['phone']!.enabled, isFalse);

      final all = ump.check({'mode': 'all'});
      expect(all['email']!.enabled, isTrue);
      expect(all['phone']!.enabled, isTrue);
    });
  });

  group('oneOf rule', () {
    test('oneOf with explicit activeBranch', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: false),
          'sms': FieldDef(required: false),
        },
        rules: [
          oneOf('contact', {
            'channel1': ['email'],
            'channel2': ['sms'],
          }, activeBranch: 'channel2'),
        ],
      );

      final avail = ump.check({'email': 'a@b.com', 'sms': '+123'});
      expect(avail['email']!.enabled, isFalse);
      expect(avail['sms']!.enabled, isTrue);
    });

    test('oneOf with empty branch should throw', () {
      expect(
        () => oneOf('group', {'empty': []}),
        throwsArgumentError,
      );
    });

    test('oneOf with field in multiple branches should throw', () {
      expect(
        () => oneOf('group', {
          'b1': ['shared', 'f1'],
          'b2': ['shared', 'f2'],
        }),
        throwsArgumentError,
      );
    });
  });

  group('anyOf rule', () {
    test('anyOf with mixed constraint rules should throw', () {
      expect(
        () => umpire_rules.anyOf([
          enabledWhen('field',
            predicate: (v, c) => true,
          ),
          fairWhen('field',
            predicate: (val, v, c) => true,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('anyOf with empty rules list should throw', () {
      expect(
        () => umpire_rules.anyOf([]),
        throwsArgumentError,
      );
    });
  });

  group('requires rule', () {
    test('requires with no dependency and no when should throw', () {
      expect(
        () => requires('field'),
        throwsArgumentError,
      );
    });
  });
}
