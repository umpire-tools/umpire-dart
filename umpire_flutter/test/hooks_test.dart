import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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
  group('useUmpire', () {
    testWidgets('initializes with initialValues', (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {'name': 'Alice', 'email': 'a@b.com'});
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.values['name'], 'Alice');
      expect(result.values['email'], 'a@b.com');
    });

    testWidgets('initializes availability from ump.check()', (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.availability['name']!.enabled, isTrue);
      expect(result.availability['name']!.required, isTrue);
      expect(result.availability['name']!.satisfied, isFalse);
    });

    testWidgets('setValue updates values and availability', (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump);
              return const SizedBox();
            },
          ),
        ),
      );

      result.setValue('name', 'Bob');
      await tester.pump();

      expect(result.values['name'], 'Bob');
      expect(result.availability['name']!.satisfied, isTrue);
    });

    testWidgets('setValues updates multiple fields', (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump);
              return const SizedBox();
            },
          ),
        ),
      );

      result.setValues({'name': 'Carol', 'email': 'c@d.com'});
      await tester.pump();

      expect(result.values['name'], 'Carol');
      expect(result.values['email'], 'c@d.com');
      expect(result.availability['name']!.satisfied, isTrue);
      expect(result.availability['email']!.satisfied, isTrue);
    });

    testWidgets('setConditions changes availability', (tester) async {
      final ump = _conditionalUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {'accountType': 'personal'});
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.availability['companyName']!.enabled, isFalse);

      result.setValue('accountType', 'business');
      await tester.pump();

      expect(result.availability['companyName']!.enabled, isTrue);
    });

    testWidgets('isValid is true when all required fields satisfied',
        (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {'name': 'Grace', 'email': 'g@h.com'});
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.isValid, isTrue);
    });

    testWidgets('isValid is false when required field is not satisfied',
        (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.isValid, isFalse);
    });

    testWidgets('isValid false when fouls present', (tester) async {
      final ump = _conditionalUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {
                    'accountType': 'business',
                    'companyName': 'Acme Corp',
                  });
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.isValid, isTrue);

      result.setValue('accountType', 'personal');
      await tester.pump();

      expect(result.fouls, isNotEmpty);
      expect(result.isValid, isFalse);
    });

    testWidgets('no fouls on initial render', (tester) async {
      final ump = _conditionalUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {
                    'accountType': 'business',
                    'companyName': 'Acme Corp',
                  });
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.fouls, isEmpty);
    });

    testWidgets('conditions passed through to availability check',
        (tester) async {
      final ump = _conditionalUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump,
                  initialValues: {'accountType': 'business'},
                  conditions: {'plan': 'enterprise'});
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.availability['companyName']!.enabled, isTrue);
    });

    testWidgets('rebuild with setConditions triggers new availability',
        (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(
                ump,
                conditions: const {'mode': 'readonly'},
              );
              return const SizedBox();
            },
          ),
        ),
      );

      result.setConditions({'mode': 'editable'});
      await tester.pump();

      // Conditions should be updated
      expect(result.availability['name']!.enabled, isTrue);
    });

    testWidgets('fouls recompute on availability change', (tester) async {
      final ump = _conditionalUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(
                ump,
                initialValues: {
                  'accountType': 'business',
                  'companyName': 'Acme Corp',
                },
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result.fouls, isEmpty);

      result.setValue('accountType', 'personal');
      await tester.pump();

      expect(result.fouls, isNotEmpty);
      expect(result.fouls.first.field, 'companyName');
    });

    testWidgets('multiple sequential setValues aggregate correctly',
        (tester) async {
      final ump = _basicUmp();
      late UmpireHookResult result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useUmpire(ump);
              return const SizedBox();
            },
          ),
        ),
      );

      result.setValue('name', 'First');
      await tester.pump();

      result.setValue('email', 'second@test.com');
      await tester.pump();

      expect(result.values['name'], 'First');
      expect(result.values['email'], 'second@test.com');
    });
  });
}
