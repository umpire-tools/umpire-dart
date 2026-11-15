import 'package:test/test.dart';
import 'package:umpire/umpire.dart' hide anyOf;

// Use a separate import for the umpire anyOf to avoid clash with matcher's anyOf
import 'package:umpire/src/rules/any_of.dart' as umpire_rules;

void main() {
  group('umpire()', () {
    test('rejects unknown fields in rules', () {
      expect(
        () => umpire(
          fields: {'email': FieldDef()},
          rules: [
            requires('unknown', dependency: 'email'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown sources in rules', () {
      expect(
        () => umpire(
          fields: {'email': FieldDef()},
          rules: [
            disables('unknown', ['email']),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Umpire.check()', () {
    test('basic required fields are enabled and required', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: true),
          'name': FieldDef(required: false),
        },
        rules: [],
      );

      final avail = ump.check({});

      expect(avail['email']!.enabled, isTrue);
      expect(avail['email']!.required, isTrue);
      expect(avail['name']!.enabled, isTrue);
      expect(avail['name']!.required, isFalse);
    });

    test('fields are marked satisfied based on isEmpty strategy', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
        },
        rules: [],
      );

      expect(ump.check({'email': ''})['email']!.satisfied, isFalse);
      expect(ump.check({'email': 'a@b.com'})['email']!.satisfied, isTrue);
    });

    test('enabledWhen disables field when predicate returns false', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: true),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );

      // Personal account — companyName disabled
      final personal = ump.check({'accountType': 'personal'});
      expect(personal['companyName']!.enabled, isFalse);
      expect(personal['companyName']!.required, isFalse);

      // Business account — companyName enabled
      final business = ump.check({'accountType': 'business'});
      expect(business['companyName']!.enabled, isTrue);
      expect(business['companyName']!.required, isTrue);
    });

    test('enabledWhen provides reason when disabled', () {
      final ump = umpire(
        fields: {'field': FieldDef()},
        rules: [
          enabledWhen('field',
            predicate: (v, c) => false,
            reason: 'Not allowed',
          ),
        ],
      );

      final avail = ump.check({});
      expect(avail['field']!.enabled, isFalse);
      expect(avail['field']!.reason, 'Not allowed');
    });

    test('requires disables target when dependency is not satisfied', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: false),
        },
        rules: [
          requires('companyName', dependency: 'accountType'),
        ],
      );

      // accountType present — enabled
      final withVal = ump.check({'accountType': 'business'});
      expect(withVal['companyName']!.enabled, isTrue);

      // accountType missing — disabled
      final without = ump.check({});
      expect(without['companyName']!.enabled, isFalse);
      expect(without['companyName']!.reason, 'requires accountType');
    });

    test('requires with when predicate', () {
      final ump = umpire(
        fields: {
          'status': FieldDef(required: true),
          'reason': FieldDef(required: false),
        },
        rules: [
          requires('reason',
            when: (v, c) => v['status'] == 'rejected',
            reason: 'A reason is required for rejected status',
          ),
        ],
      );

      // status is 'rejected' → when returns true → requirement met → enabled
      final rejected = ump.check({'status': 'rejected'});
      expect(rejected['reason']!.enabled, isTrue);

      // status is 'approved' → when returns false → requirement NOT met → disabled
      final approved = ump.check({'status': 'approved'});
      expect(approved['reason']!.enabled, isFalse);
    });

    test('disables disables targets when source is satisfied', () {
      final ump = umpire(
        fields: {
          'preferContact': FieldDef(),
          'email': FieldDef(),
          'phone': FieldDef(),
        },
        rules: [
          disables('preferContact', ['email', 'phone']),
        ],
      );

      final withPrefer = ump.check({'preferContact': true});
      expect(withPrefer['email']!.enabled, isFalse);
      expect(withPrefer['phone']!.enabled, isFalse);

      final without = ump.check({});
      expect(without['email']!.enabled, isTrue);
      expect(without['phone']!.enabled, isTrue);
    });

    test('fairWhen marks field unfair when predicate returns false', () {
      final ump = umpire(
        fields: {
          'planId': FieldDef(required: true),
          'companyName': FieldDef(required: true),
        },
        rules: [
          fairWhen('planId',
            predicate: (val, v, c) => ['pro', 'team'].contains(val),
          ),
        ],
      );

      final valid = ump.check({'planId': 'pro'});
      expect(valid['planId']!.enabled, isTrue);
      expect(valid['planId']!.fair, isTrue);

      final invalid = ump.check({'planId': 'free'});
      expect(invalid['planId']!.enabled, isTrue);
      expect(invalid['planId']!.fair, isFalse);
      expect(invalid['planId']!.reason, 'selection is no longer valid');
    });

    test('fairWhen is ignored when value is not satisfied', () {
      final ump = umpire(
        fields: {'planId': FieldDef(required: true)},
        rules: [
          fairWhen('planId',
            predicate: (val, v, c) => val == 'pro',
          ),
        ],
      );

      // No value — fairWhen should not apply
      final avail = ump.check({});
      expect(avail['planId']!.enabled, isTrue);
      expect(avail['planId']!.fair, isTrue);
    });

    test('oneOf enables only the branch with satisfied fields', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: false),
          'sms': FieldDef(required: false),
          'push': FieldDef(required: false),
        },
        rules: [
          oneOf('notifications', {
            'channel1': ['email'],
            'channel2': ['sms', 'push'],
          }),
        ],
      );

      final withEmail = ump.check({'email': 'a@b.com'});
      expect(withEmail['email']!.enabled, isTrue);
      expect(withEmail['sms']!.enabled, isFalse);
      expect(withEmail['push']!.enabled, isFalse);

      final withSms = ump.check({'sms': '+123'});
      expect(withSms['email']!.enabled, isFalse);
      expect(withSms['sms']!.enabled, isTrue);
      expect(withSms['push']!.enabled, isTrue);
    });

    test('conditions are passed through to predicates', () {
      final ump = umpire(
        fields: {'field': FieldDef()},
        rules: [
          enabledWhen('field',
            predicate: (v, c) => c['isAdmin'] == true,
          ),
        ],
      );

      final admin = ump.check({}, conditions: {'isAdmin': true});
      expect(admin['field']!.enabled, isTrue);

      final nonAdmin = ump.check({}, conditions: {'isAdmin': false});
      expect(nonAdmin['field']!.enabled, isFalse);
    });
  });

  group('Umpire.play()', () {
    test('foul when field transitions from enabled to disabled', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: false, defaultValue: null),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );

      // Business: companyName is enabled and has a value
      final before = ump.check({
        'accountType': 'business',
        'companyName': 'ACME Corp',
      });

      // Changed to personal: companyName becomes disabled
      final after = ump.check({
        'accountType': 'personal',
        'companyName': 'ACME Corp',
      });

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'accountType': 'personal', 'companyName': 'ACME Corp'},
      );

      expect(fouls.length, greaterThan(0));
      expect(fouls.first.field, 'companyName');
      expect(fouls.first.suggestedValue, null);
    });

    test('no foul when field already disabled in both states', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: false),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );

      final before = ump.check({'accountType': 'personal'});
      final after = ump.check({'accountType': 'personal'});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'accountType': 'personal'},
      );

      expect(fouls, isEmpty);
    });

    test('no foul when value already matches suggested default', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: false, defaultValue: null),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );

      // Before: business account with no companyName set
      // After: personal account
      final before = ump.check({'accountType': 'business', 'companyName': null});
      final after = ump.check({'accountType': 'personal', 'companyName': null});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'accountType': 'personal', 'companyName': null},
      );

      // companyName already null (the default) — no foul needed
      expect(fouls.where((f) => f.field == 'companyName'), isEmpty);
    });

    test('foul on fair→unfair transition', () {
      final ump = umpire(
        fields: {
          'planId': FieldDef(required: true, defaultValue: null),
        },
        rules: [
          fairWhen('planId',
            predicate: (val, v, c) => val == 'pro',
          ),
        ],
      );

      final before = ump.check({'planId': 'pro'});
      final after = ump.check({'planId': 'free'});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'planId': 'free'},
      );

      expect(fouls, isNotEmpty);
      expect(fouls.first.field, 'planId');
    });
  });

  group('Umpire.init()', () {
    test('initializes values from field defaults', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(defaultValue: ''),
          'type': FieldDef(defaultValue: 'personal'),
        },
        rules: [],
      );

      final values = ump.init();
      expect(values['email'], '');
      expect(values['type'], 'personal');
    });

    test('overrides merge with defaults', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(defaultValue: ''),
          'type': FieldDef(defaultValue: 'personal'),
        },
        rules: [],
      );

      final values = ump.init({'email': 'user@test.com'});
      expect(values['email'], 'user@test.com');
      expect(values['type'], 'personal');
    });
  });

  group('anyOf', () {
    test('passes when any inner rule passes', () {
      final ump = umpire(
        fields: {'field': FieldDef(required: true)},
        rules: [
          umpire_rules.anyOf([
            enabledWhen('field',
              predicate: (v, c) => false,
              reason: 'first fails',
            ),
            enabledWhen('field',
              predicate: (v, c) => true,
              reason: 'second passes',
            ),
          ]),
        ],
      );

      final avail = ump.check({'field': 'value'});
      expect(avail['field']!.enabled, isTrue);
    });

    test('fails when all inner rules fail', () {
      final ump = umpire(
        fields: {'field': FieldDef(required: true)},
        rules: [
          umpire_rules.anyOf([
            enabledWhen('field',
              predicate: (v, c) => false,
              reason: 'first fails',
            ),
            enabledWhen('field',
              predicate: (v, c) => false,
              reason: 'second fails',
            ),
          ]),
        ],
      );

      final avail = ump.check({'field': 'value'});
      expect(avail['field']!.enabled, isFalse);
    });
  });

  group('Umpire.check() — multiple dependencies', () {
    test('requires with multiple dependencies chains evaluation', () {
      final ump = umpire(
        fields: {
          'a': FieldDef(required: false),
          'b': FieldDef(required: false),
          'c': FieldDef(required: false),
        },
        rules: [
          requires('b', dependency: 'a'),
          requires('c', dependency: 'b'),
        ],
      );

      final empty = ump.check({});
      expect(empty['a']!.enabled, isTrue);
      expect(empty['b']!.enabled, isFalse);
      expect(empty['c']!.enabled, isFalse);

      final justA = ump.check({'a': 'value'});
      expect(justA['a']!.enabled, isTrue);
      expect(justA['b']!.enabled, isTrue);
      expect(justA['c']!.enabled, isFalse);

      final ab = ump.check({'a': 'value', 'b': 'value'});
      expect(ab['a']!.enabled, isTrue);
      expect(ab['b']!.enabled, isTrue);
      expect(ab['c']!.enabled, isTrue);
    });
  });

  group('Umpire.check() — enabledWhen with reason', () {
    test('enabledWhen provides custom reason via constructor', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'vatNumber': FieldDef(required: false),
        },
        rules: [
          enabledWhen('vatNumber',
            predicate: (v, c) => v['accountType'] == 'business',
            reason: 'VAT number only applies to business accounts',
          ),
        ],
      );

      final personal = ump.check({'accountType': 'personal'});
      expect(personal['vatNumber']!.enabled, isFalse);
      expect(personal['vatNumber']!.reason, 'VAT number only applies to business accounts');
    });
  });

  group('Umpire.check() — field availability when disabled', () {
    test('required is false when field is disabled', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(required: true),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );

      final personal = ump.check({'accountType': 'personal'});
      expect(personal['companyName']!.enabled, isFalse);
      expect(personal['companyName']!.required, isFalse);
    });

    test('validators report nothing for a disabled field', () {
      final ump = umpire(
        fields: {'email': FieldDef()},
        rules: [
          enabledWhen('email', predicate: (v, c) => c['on'] == true),
        ],
        validators: {
          'email': ValidatorEntry(
            op: checkOps.email(),
            error: 'Enter a valid email address',
          ),
        },
      );

      final disabled = ump.check({'email': 'not-an-email'},
          conditions: {'on': false});
      expect(disabled['email']!.valid, isNull);
      expect(disabled['email']!.error, isNull);

      final enabled = ump.check({'email': 'not-an-email'},
          conditions: {'on': true});
      expect(enabled['email']!.valid, isFalse);
      expect(enabled['email']!.error, 'Enter a valid email address');
    });
  });

  group('Umpire.check() — gate vs fair precedence', () {
    test('gate disabled means fair rules are skipped', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'planId': FieldDef(required: false),
        },
        rules: [
          enabledWhen('planId',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
          fairWhen('planId',
            predicate: (val, v, c) => ['pro', 'team'].contains(val),
          ),
        ],
      );

      final personal = ump.check({'accountType': 'personal', 'planId': 'free'});
      expect(personal['planId']!.enabled, isFalse);
      expect(personal['planId']!.fair, isTrue);

      final business = ump.check({'accountType': 'business', 'planId': 'free'});
      expect(business['planId']!.enabled, isTrue);
      expect(business['planId']!.fair, isFalse);
    });

    test('same field targeted by both gate and fair rules', () {
      final ump = umpire(
        fields: {
          'role': FieldDef(required: true),
          'specialField': FieldDef(required: false),
        },
        rules: [
          enabledWhen('specialField',
            predicate: (v, c) => v['role'] == 'admin',
          ),
          fairWhen('specialField',
            predicate: (val, v, c) => val == 'allowed-value',
          ),
        ],
      );

      final nonAdmin = ump.check({'role': 'user', 'specialField': 'wrong'});
      expect(nonAdmin['specialField']!.enabled, isFalse);
      expect(nonAdmin['specialField']!.fair, isTrue);
    });
  });

  group('Umpire.check() — empty rules', () {
    test('empty rules list produces default availability', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: true),
          'name': FieldDef(required: false),
        },
        rules: [],
      );

      final avail = ump.check({'email': 'test@test.com'});
      expect(avail['email']!.enabled, isTrue);
      expect(avail['email']!.required, isTrue);
      expect(avail['email']!.fair, isTrue);
      expect(avail['name']!.enabled, isTrue);
      expect(avail['name']!.required, isFalse);
    });
  });
}
