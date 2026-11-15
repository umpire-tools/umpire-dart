import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

void main() {
  group('UmpireSchema.fromJson', () {
    test('parses a minimal valid schema and builds a working Umpire', () {
      final json = {
        'version': 1,
        'fields': {
          'email': {'required': true, 'isEmpty': 'string'},
          'name': {'required': false},
        },
        'rules': [],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();
      final avail = ump.check({'email': 'a@b.com'});
      expect(avail['email']!.enabled, isTrue);
      expect(avail['email']!.required, isTrue);
    });

    test('rejects unsupported schema version', () {
      expect(
        () => UmpireSchema.fromJson({'version': 2}),
        throwsA(isA<UmpireSchemaException>()),
      );
      expect(
        () => UmpireSchema.fromJson({'version': 0}),
        throwsA(isA<UmpireSchemaException>()),
      );
      expect(
        () => UmpireSchema.fromJson({}),
        throwsA(isA<UmpireSchemaException>()),
      );
    });

    test('handles excluded section with print warnings (does not block)', () {
      final json = {
        'version': 1,
        'fields': {'email': {'required': true}},
        'rules': [],
        'excluded': [
          {
            'type': 'requires',
            'field': 'email',
            'description': 'not supported in JSON mode',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      expect(schema.excluded.length, 1);
    });

    test('parses conditions with correct types', () {
      final json = {
        'version': 1,
        'conditions': {
          'isAdmin': {'type': 'boolean'},
          'tier': {'type': 'string'},
          'validPlans': {'type': 'string[]'},
        },
        'fields': {'email': {'required': true}},
        'rules': [],
      };
      final schema = UmpireSchema.fromJson(json);
      expect(schema.conditions['isAdmin']!.type, 'boolean');
      expect(schema.conditions['tier']!.type, 'string');
      expect(schema.conditions['validPlans']!.type, 'string[]');
    });

    test('parses fields with isEmpty strategy mapping', () {
      final json = {
        'version': 1,
        'fields': {
          'a': {'isEmpty': 'string'},
          'b': {'isEmpty': 'number'},
          'c': {'isEmpty': 'boolean'},
          'd': {'isEmpty': 'array'},
          'e': {'required': false},
        },
        'rules': [],
      };
      final schema = UmpireSchema.fromJson(json);
      expect(schema.fields['a']!.isEmpty, IsEmptyStrategy.string);
      expect(schema.fields['b']!.isEmpty, IsEmptyStrategy.number);
      expect(schema.fields['c']!.isEmpty, IsEmptyStrategy.boolean);
      expect(schema.fields['d']!.isEmpty, IsEmptyStrategy.array);
      expect(schema.fields['e']!.isEmpty, IsEmptyStrategy.present);
    });

    test('reads field defaults so init() seeds them', () {
      final json = {
        'version': 1,
        'fields': {
          'note': {'default': 'not inserted during check'},
          'empty': <String, dynamic>{},
        },
        'rules': [],
      };
      final schema = UmpireSchema.fromJson(json);
      expect(schema.build().init(),
          {'note': 'not inserted during check', 'empty': null});
    });

    test('rejects undeclared members on closed objects', () {
      Map<String, dynamic> schema(Map<String, dynamic> overrides) => {
            'version': 1,
            'fields': {
              'email': <String, dynamic>{},
            },
            'rules': <dynamic>[],
            ...overrides,
          };

      expect(
        () => UmpireSchema.fromJson(schema({'unexpected': true})),
        throwsA(isA<UmpireSchemaException>()
            .having((e) => e.message, 'message', contains('unexpected'))),
      );
      expect(
        () => UmpireSchema.fromJson(schema({
              'fields': {
                'email': {'description': 'not part of v1'},
              },
            })),
        throwsA(isA<UmpireSchemaException>()
            .having((e) => e.message, 'message', contains('description'))),
      );
      expect(
        () => UmpireSchema.fromJson(schema({'fields': <String, dynamic>{}})),
        throwsA(isA<UmpireSchemaException>()),
      );
    });

    test('rejects undeclared members in nested rules and expressions', () {
      void expectNestedRejection(Map<String, dynamic> rule) {
        expect(
          () => UmpireSchema.fromJson({
            'version': 1,
            'fields': {'a': <String, dynamic>{}, 'b': <String, dynamic>{}},
            'rules': [rule],
          }),
          throwsA(isA<UmpireSchemaException>()
              .having((e) => e.message, 'message', contains('unexpected'))),
        );
      }

      expectNestedRejection({
        'type': 'anyOf',
        'rules': [
          {
            'type': 'enabledWhen',
            'field': 'a',
            'when': {'op': 'truthy', 'field': 'b'},
            'unexpected': true,
          },
        ],
      });

      expectNestedRejection({
        'type': 'eitherOf',
        'group': 'g',
        'branches': {
          'x': [
            {
              'type': 'requires',
              'field': 'a',
              'dependency': 'b',
              'unexpected': true,
            },
          ],
        },
      });

      expectNestedRejection({
        'type': 'enabledWhen',
        'field': 'a',
        'when': {
          'op': 'and',
          'exprs': [
            {'op': 'truthy', 'field': 'b', 'unexpected': true},
          ],
        },
      });

      expectNestedRejection({
        'type': 'enabledWhen',
        'field': 'a',
        'when': {
          'op': 'or',
          'exprs': [
            {'op': 'truthy', 'field': 'b', 'unexpected': true},
          ],
        },
      });

      expectNestedRejection({
        'type': 'enabledWhen',
        'field': 'a',
        'when': {
          'op': 'not',
          'expr': {'op': 'truthy', 'field': 'b', 'unexpected': true},
        },
      });

      expectNestedRejection({
        'type': 'requires',
        'field': 'a',
        'dependencies': [
          {'op': 'truthy', 'field': 'b', 'unexpected': true},
        ],
      });
    });

    test('rejects the disables field alias and oneOf activeBranch', () {
      expect(
        () => UmpireSchema.fromJson({
          'version': 1,
          'fields': {'a': <String, dynamic>{}, 'b': <String, dynamic>{}},
          'rules': [
            {'type': 'disables', 'field': 'a', 'targets': ['b']},
          ],
        }),
        throwsA(isA<UmpireSchemaException>()
            .having((e) => e.message, 'message', contains('field'))),
      );

      expect(
        () => UmpireSchema.fromJson({
          'version': 1,
          'fields': {'a': <String, dynamic>{}, 'b': <String, dynamic>{}},
          'rules': [
            {
              'type': 'oneOf',
              'group': 'g',
              'branches': {
                'x': ['a'],
              },
              'activeBranch': 'x',
            },
          ],
        }),
        throwsA(isA<UmpireSchemaException>()
            .having((e) => e.message, 'message', contains('activeBranch'))),
      );
    });

    test('accepts a contains expression on an array field', () {
      final json = {
        'version': 1,
        'fields': {
          'tags': {'isEmpty': 'array'},
          'note': <String, dynamic>{},
        },
        'rules': [
          {
            'type': 'enabledWhen',
            'field': 'note',
            'when': {'op': 'contains', 'field': 'tags', 'value': 'urgent'},
          }
        ],
      };
      final ump = UmpireSchema.fromJson(json).build();

      expect(ump.check({'tags': ['urgent']})['note']!.enabled, isTrue);
      expect(ump.check({'tags': ['routine']})['note']!.enabled, isFalse);
    });

    test('parses validators map', () {
      final json = {
        'version': 1,
        'fields': {'email': {'required': true}},
        'rules': [],
        'validators': {'email': {'op': 'email', 'error': 'Invalid email'}},
      };
      final schema = UmpireSchema.fromJson(json);
      expect(schema.validators['email']['op'], 'email');
    });
  });

  group('UmpireSchema.build', () {
    test('resolves static ConditionProvider values', () {
      final json = {
        'version': 1,
        'fields': {'email': {'required': true}},
        'rules': [
          {
            'type': 'enabledWhen',
            'field': 'email',
            'when': {'op': 'cond', 'condition': 'isAdmin'},
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build(
        conditions: {'isAdmin': ConditionProvider.value(true)},
      );
      final avail = ump.check({'email': 'test@test.com'},
          conditions: {'isAdmin': true});
      expect(avail['email']!.enabled, isTrue);

      final avail2 = ump.check({'email': 'test@test.com'},
          conditions: {'isAdmin': false});
      expect(avail2['email']!.enabled, isFalse);
    });

    test('merges native rules passed via rules parameter', () {
      final json = {
        'version': 1,
        'fields': {
          'email': {'required': true},
          'name': {'required': false},
        },
        'rules': [
          {
            'type': 'requires',
            'field': 'name',
            'when': {'op': 'truthy', 'field': 'email'},
            'reason': 'Name required with email',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build(
        rules: [
          fairWhen('email',
            predicate: (val, v, c) => val.toString().contains('@'),
            reason: 'Must be an email address',
          ),
        ],
      );

      final avail = ump.check({'email': 'a@b.com'});
      expect(avail['name']!.enabled, isTrue);
      expect(avail['email']!.fair, isTrue);

      final avail2 = ump.check({'email': 'invalid'});
      expect(avail2['name']!.enabled, isTrue);
      expect(avail2['email']!.fair, isFalse);
    });

    test('builds check rules that mark field as unfair on validation failure',
        () {
      final json = {
        'version': 1,
        'fields': {'email': {'required': true}},
        'rules': [
          {
            'type': 'check',
            'field': 'email',
            'op': 'email',
            'reason': 'Must be a valid email',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final invalid = ump.check({'email': 'not-an-email'});
      expect(invalid['email']!.enabled, isTrue);
      expect(invalid['email']!.fair, isFalse);
      expect(invalid['email']!.reason, 'Must be a valid email');

      final valid = ump.check({'email': 'user@test.com'});
      expect(valid['email']!.enabled, isTrue);
      expect(valid['email']!.fair, isTrue);
    });

    test('builds requires rule with dependency from JSON', () {
      final json = {
        'version': 1,
        'fields': {
          'accountType': {'required': true},
          'companyName': {'required': false},
        },
        'rules': [
          {
            'type': 'requires',
            'field': 'companyName',
            'dependency': 'accountType',
            'reason': 'Company name is required for accounts',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final withVal = ump.check({'accountType': 'business'});
      expect(withVal['companyName']!.enabled, isTrue);

      final without = ump.check({});
      expect(without['companyName']!.enabled, isFalse);
    });

    test('builds requires rule with when expression from JSON', () {
      final json = {
        'version': 1,
        'fields': {
          'status': {'required': true},
          'reason': {'required': false},
        },
        'rules': [
          {
            'type': 'requires',
            'field': 'reason',
            'when': {'op': 'eq', 'field': 'status', 'value': 'rejected'},
            'reason': 'Reason required when rejected',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final rejected = ump.check({'status': 'rejected'});
      expect(rejected['reason']!.enabled, isTrue);

      final approved = ump.check({'status': 'approved'});
      expect(approved['reason']!.enabled, isFalse);
    });

    test('builds enabledWhen rule from JSON', () {
      final json = {
        'version': 1,
        'fields': {
          'accountType': {'required': true},
          'vatNumber': {'required': false},
        },
        'rules': [
          {
            'type': 'enabledWhen',
            'field': 'vatNumber',
            'when': {'op': 'eq', 'field': 'accountType', 'value': 'business'},
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final business = ump.check({'accountType': 'business'});
      expect(business['vatNumber']!.enabled, isTrue);

      final personal = ump.check({'accountType': 'personal'});
      expect(personal['vatNumber']!.enabled, isFalse);
    });

    test('builds fairWhen rule from JSON', () {
      final json = {
        'version': 1,
        'fields': {'planId': {'required': true}},
        'rules': [
          {
            'type': 'fairWhen',
            'field': 'planId',
            'when': {
              'op': 'condIn',
              'condition': 'allowedPlans',
              'values': ['pro', 'team']
            },
            'reason': 'Plan not available',
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final fair = ump.check({'planId': 'pro'},
          conditions: {'allowedPlans': 'pro'});
      expect(fair['planId']!.fair, isTrue);

      final unfair = ump.check({'planId': 'free'},
          conditions: {'allowedPlans': 'free'});
      expect(unfair['planId']!.fair, isFalse);
    });

    test('builds disables rule from JSON', () {
      final json = {
        'version': 1,
        'fields': {
          'preferContact': {'required': false},
          'email': {'required': false},
          'phone': {'required': false},
        },
        'rules': [
          {
            'type': 'disables',
            'source': 'preferContact',
            'targets': ['email', 'phone'],
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final withPref = ump.check({'preferContact': true});
      expect(withPref['email']!.enabled, isFalse);
      expect(withPref['phone']!.enabled, isFalse);
    });

    test('builds oneOf rule from JSON', () {
      final json = {
        'version': 1,
        'fields': {
          'email': {'required': false},
          'sms': {'required': false},
        },
        'rules': [
          {
            'type': 'oneOf',
            'group': 'contact',
            'branches': {'channel1': ['email'], 'channel2': ['sms']},
          }
        ],
      };
      final schema = UmpireSchema.fromJson(json);
      final ump = schema.build();

      final avail = ump.check({'email': 'a@b.com'});
      expect(avail['email']!.enabled, isTrue);
      expect(avail['sms']!.enabled, isFalse);
    });
  });
}
