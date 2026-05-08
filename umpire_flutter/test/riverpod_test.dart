import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umpire/umpire.dart';
import 'package:umpire_flutter/umpire_flutter.dart';

Umpire _basicUmp() => umpire(
      fields: {
        'name': FieldDef(required: true, defaultValue: '', isEmpty: IsEmptyStrategy.string),
        'email': FieldDef(required: true, defaultValue: '', isEmpty: IsEmptyStrategy.string),
      },
      rules: [],
    );

Umpire _conditionalUmp() => umpire(
      fields: {
        'accountType': FieldDef(required: true),
        'companyName': FieldDef(required: true, defaultValue: '', isEmpty: IsEmptyStrategy.string),
      },
      rules: [
        enabledWhen('companyName',
          predicate: (v, c) => v['accountType'] == 'business',
        ),
      ],
    );

void main() {
  group('UmpireState', () {
    test('isValid is true when all required fields satisfied', () {
      final ump = _basicUmp();
      final state = UmpireState(
        values: {'name': 'Alice', 'email': 'a@b.com'},
        availability: ump.check({'name': 'Alice', 'email': 'a@b.com'}),
        fouls: const [],
      );

      expect(state.isValid, isTrue);
    });

    test('isValid is false when required field is not satisfied', () {
      final ump = _basicUmp();
      final state = UmpireState(
        values: const {},
        availability: ump.check(const {}),
        fouls: const [],
      );

      expect(state.isValid, isFalse);
    });

    test('isValid is false when fouls are present', () {
      final ump = _basicUmp();
      final state = UmpireState(
        values: const {},
        availability: ump.check(const {}),
        fouls: const [Foul(field: 'name', reason: 'disabled')],
      );

      expect(state.isValid, isFalse);
    });
  });

  group('UmpireNotifier', () {
    test('initializes with defaults from ump.init()', () {
      final ump = _basicUmp();
      final notifier = UmpireNotifier(ump);

      expect(notifier.state.values['name'], '');
      expect(notifier.state.values['email'], '');
      expect(notifier.state.fouls, isEmpty);
    });

    test('initializes with conditions', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(
        ump,
        conditions: {'plan': 'enterprise'},
      );

      expect(notifier.state.conditions['plan'], 'enterprise');
    });

    test('setValue updates state', () {
      final ump = _basicUmp();
      final notifier = UmpireNotifier(ump);

      notifier.setValue('name', 'Bob');

      expect(notifier.state.values['name'], 'Bob');
      expect(notifier.state.availability['name']!.satisfied, isTrue);
    });

    test('setValue produces new state reference', () {
      final ump = _basicUmp();
      final notifier = UmpireNotifier(ump);
      final oldState = notifier.state;

      notifier.setValue('name', 'Bob');

      expect(notifier.state, isNot(same(oldState)));
    });

    test('setValues updates multiple fields', () {
      final ump = _basicUmp();
      final notifier = UmpireNotifier(ump);

      notifier.setValues({'name': 'Carol', 'email': 'c@d.com'});

      expect(notifier.state.values['name'], 'Carol');
      expect(notifier.state.values['email'], 'c@d.com');
      expect(notifier.state.availability['name']!.satisfied, isTrue);
      expect(notifier.state.availability['email']!.satisfied, isTrue);
    });

    test('setConditions updates state', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(ump);

      notifier.setConditions({'plan': 'premium'});

      expect(notifier.state.conditions['plan'], 'premium');
    });

    test('fouls generated on enabled to disabled transition', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(ump);

      // Set business type first
      notifier.setValues({
        'accountType': 'business',
        'companyName': 'Acme Corp',
      });
      expect(notifier.state.fouls, isEmpty);

      // Switch to personal — creates foul
      notifier.setValue('accountType', 'personal');
      expect(notifier.state.fouls, isNotEmpty);
      expect(notifier.state.fouls.first.field, 'companyName');
    });

    test('isValid false when required field empty and fouls present', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(ump);

      notifier.setValues({
        'accountType': 'business',
        'companyName': 'Acme Corp',
      });
      expect(notifier.state.isValid, isTrue);

      notifier.setValue('accountType', 'personal');
      expect(notifier.state.isValid, isFalse);
    });

    test('conditions preserved across setValue', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(
        ump,
        conditions: {'plan': 'basic'},
      );

      notifier.setValue('accountType', 'business');

      expect(notifier.state.conditions['plan'], 'basic');
    });

    test('conditions preserved across setValues', () {
      final ump = _conditionalUmp();
      final notifier = UmpireNotifier(
        ump,
        conditions: {'plan': 'basic'},
      );

      notifier.setValues({'accountType': 'business'});

      expect(notifier.state.conditions['plan'], 'basic');
    });
  });

  group('umpireProvider', () {
    test('creates notifier via ProviderContainer', () {
      final ump = _basicUmp();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(umpireProvider(ump).notifier);

      expect(notifier, isA<UmpireNotifier>());
      expect(notifier.state.values['name'], '');
    });

    test('different Umpire instances produce different state', () {
      final ump1 = _basicUmp();
      final ump2 = umpire(
        fields: {
          'score': FieldDef(required: true, defaultValue: 0),
        },
        rules: [],
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state1 = container.read(umpireProvider(ump1));
      final state2 = container.read(umpireProvider(ump2));

      expect(state1.availability.containsKey('name'), isTrue);
      expect(state2.availability.containsKey('score'), isTrue);
    });

    test('notifier updates reflect in provider state', () {
      final ump = _basicUmp();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(umpireProvider(ump).notifier).setValue('name', 'Dave');

      final state = container.read(umpireProvider(ump));
      expect(state.values['name'], 'Dave');
    });
  });

  group('Riverpod selector pattern', () {
    test('select narrows to field availability', () {
      final ump = _conditionalUmp();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(umpireProvider(ump).notifier).setValue('accountType', 'business');

      final companyEnabled = container.read(
        umpireProvider(ump).select((s) => s.availability['companyName']?.enabled),
      );

      expect(companyEnabled, isTrue);
    });

    test('select returns updated value after mutation', () {
      final ump = _conditionalUmp();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final enabled = container.read(
        umpireProvider(ump).select((s) => s.availability['companyName']?.enabled),
      );
      expect(enabled, isFalse);

      container.read(umpireProvider(ump).notifier).setValue('accountType', 'business');

      final updated = container.read(
        umpireProvider(ump).select((s) => s.availability['companyName']?.enabled),
      );
      expect(updated, isTrue);
    });
  });
}
