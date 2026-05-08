import 'package:flutter_test/flutter_test.dart';
import 'package:umpire/umpire.dart';
import 'package:umpire_flutter/umpire_flutter.dart';

Umpire _basicUmp() => umpire(
      fields: {
        'name': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
        'email': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
      },
      rules: [],
    );

Umpire _conditionalUmp() => umpire(
      fields: {
        'accountType': FieldDef(required: true),
        'companyName': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
      },
      rules: [
        enabledWhen('companyName',
          predicate: (v, c) => v['accountType'] == 'business',
        ),
      ],
    );

void main() {
  group('UmpireController construction', () {
    test('initializes values from ump.init() when no initialValues', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      expect(controller.values['name'], isNull);
      expect(controller.values['email'], isNull);
    });

    test('uses provided initialValues over defaults', () {
      final ump = _basicUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'name': 'Alice', 'email': 'a@b.com'},
      );

      expect(controller.values['name'], 'Alice');
      expect(controller.values['email'], 'a@b.com');
    });

    test('computes initial availability', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      final avail = controller.availability;
      expect(avail['name']!.enabled, isTrue);
      expect(avail['name']!.required, isTrue);
      expect(avail['name']!.satisfied, isFalse); // null is empty string
    });

    test('passes conditions to initial check', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'accountType': 'business'},
        conditions: {'plan': 'enterprise'},
      );

      // companyName should be enabled when accountType is business
      expect(controller.availability['companyName']!.enabled, isTrue);
    });
  });

  group('UmpireController.setValue', () {
    test('updates values and availability', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      controller.setValue('name', 'Bob');

      expect(controller.values['name'], 'Bob');
      expect(controller.availability['name']!.satisfied, isTrue);
    });

    test('does not mutate original values map', () {
      final ump = _basicUmp();
      final initialValues = {'name': 'Alice'};
      final controller = UmpireController(
        ump: ump,
        initialValues: initialValues,
      );

      controller.setValue('name', 'Bob');

      expect(initialValues['name'], 'Alice');
    });
  });

  group('UmpireController.setValues', () {
    test('updates multiple fields at once', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      controller.setValues({'name': 'Carol', 'email': 'c@d.com'});

      expect(controller.values['name'], 'Carol');
      expect(controller.values['email'], 'c@d.com');
      expect(controller.availability['name']!.satisfied, isTrue);
      expect(controller.availability['email']!.satisfied, isTrue);
    });
  });

  group('UmpireController.setConditions', () {
    test('changes availability based on conditions', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'accountType': 'personal'},
      );

      // Start: companyName disabled for personal
      expect(controller.availability['companyName']!.enabled, isFalse);

      controller.setValue('accountType', 'business');
      expect(controller.availability['companyName']!.enabled, isTrue);
    });
  });

  group('UmpireController.reset', () {
    test('restores values to defaults', () {
      final ump = umpire(
        fields: {
          'name': FieldDef(required: true, defaultValue: ''),
          'email': FieldDef(required: true, defaultValue: ''),
        },
        rules: [],
      );
      final controller = UmpireController(
        ump: ump,
        initialValues: {'name': 'Dave', 'email': 'd@e.com'},
      );

      controller.reset();

      expect(controller.values['name'], '');
      expect(controller.values['email'], '');
    });

    test('recomputes availability after reset', () {
      final ump = _basicUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'name': 'Dave', 'email': 'd@e.com'},
      );

      expect(controller.availability['name']!.satisfied, isTrue);

      controller.reset();

      // After reset, values are null (default), not satisfied for strings
      expect(controller.availability['name']!.satisfied, isFalse);
    });
  });

  group('UmpireController notifyListeners', () {
    test('fires exactly once per setValue', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      var callCount = 0;
      controller.addListener(() {
        callCount++;
      });

      controller.setValue('name', 'Eve');
      expect(callCount, 1);
    });

    test('fires exactly once per setValues', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      var callCount = 0;
      controller.addListener(() {
        callCount++;
      });

      controller.setValues({'name': 'Frank', 'email': 'f@g.com'});
      expect(callCount, 1);
    });

    test('fires exactly once per setConditions', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(ump: ump);

      var callCount = 0;
      controller.addListener(() {
        callCount++;
      });

      controller.setConditions({'plan': 'premium'});
      expect(callCount, 1);
    });

    test('fires exactly once per reset', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      var callCount = 0;
      controller.addListener(() {
        callCount++;
      });

      controller.reset();
      expect(callCount, 1);
    });
  });

  group('UmpireController.isValid', () {
    test('true when all required fields satisfied and no fouls', () {
      final ump = _basicUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'name': 'Grace', 'email': 'g@h.com'},
      );

      expect(controller.isValid, isTrue);
    });

    test('false when a required field is not satisfied', () {
      final ump = _basicUmp();
      final controller = UmpireController(ump: ump);

      // name is null, isEmptyStrategy is string → not satisfied
      expect(controller.isValid, isFalse);
    });

    test('false when fouls are present', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {
          'accountType': 'business',
          'companyName': 'Acme Corp',
        },
      );

      expect(controller.isValid, isTrue);

      // Switch to personal — companyName gets disabled, creating a foul
      controller.setValue('accountType', 'personal');

      expect(controller.fouls, isNotEmpty);
      expect(controller.isValid, isFalse);
    });

    test('false when a check error exists', () {
      final ump = umpire(
        fields: {
          'age': FieldDef(required: true, isEmpty: IsEmptyStrategy.number),
        },
        rules: [],
        validators: {
          'age': ValidatorEntry(
            op: checkOps.min(19),
            error: 'Must be over 18',
          ),
        },
      );
      final controller = UmpireController(
        ump: ump,
        initialValues: {'age': 15},
      );

      expect(controller.availability['age']!.valid, isFalse);
      expect(controller.isValid, isFalse);
    });

    test('true when check passes and field is satisfied', () {
      final ump = umpire(
        fields: {
          'age': FieldDef(required: true, isEmpty: IsEmptyStrategy.number),
        },
        rules: [],
        validators: {
          'age': ValidatorEntry(
            op: checkOps.min(19),
            error: 'Must be over 18',
          ),
        },
      );
      final controller = UmpireController(
        ump: ump,
        initialValues: {'age': 25},
      );

      expect(controller.availability['age']!.valid, isTrue);
      expect(controller.isValid, isTrue);
    });
  });

  group('UmpireController fouls', () {
    test('generates foul on enabled to disabled transition', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {
          'accountType': 'business',
          'companyName': 'Acme Corp',
        },
      );

      expect(controller.fouls, isEmpty);

      controller.setValue('accountType', 'personal');

      expect(controller.fouls, isNotEmpty);
      expect(controller.fouls.first.field, 'companyName');
    });

    test('no foul when value matches default', () {
      final ump = umpire(
        fields: {
          'accountType': FieldDef(required: true),
          'companyName': FieldDef(
            required: true,
            defaultValue: '',
          ),
        },
        rules: [
          enabledWhen('companyName',
            predicate: (v, c) => v['accountType'] == 'business',
          ),
        ],
      );
      final controller = UmpireController(
        ump: ump,
        initialValues: {
          'accountType': 'business',
          'companyName': '',
        },
      );

      controller.setValue('accountType', 'personal');

      // Value matches default, no foul
      expect(controller.fouls, isEmpty);
    });

    test('fouls clear when reset', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {
          'accountType': 'business',
          'companyName': 'Acme Corp',
        },
      );

      controller.setValue('accountType', 'personal');
      expect(controller.fouls, isNotEmpty);

      controller.reset();
      expect(controller.fouls, isEmpty);
    });
  });

  group('UmpireController availability updates', () {
    test('reflects rule changes when values change', () {
      final ump = _conditionalUmp();
      final controller = UmpireController(
        ump: ump,
        initialValues: {'accountType': 'personal'},
      );

      expect(controller.availability['companyName']!.enabled, isFalse);
      expect(controller.availability['companyName']!.required, isFalse);

      controller.setValue('accountType', 'business');

      expect(controller.availability['companyName']!.enabled, isTrue);
      expect(controller.availability['companyName']!.required, isTrue);
    });
  });
}
