import 'package:test/test.dart';
import 'package:umpire/umpire.dart';

void main() {
  group('Umpire — zero vs null values', () {
    test('zero value is satisfied, null is not', () {
      final ump = umpire(
        fields: {
          'count': FieldDef(required: true, isEmpty: IsEmptyStrategy.number),
          'name': FieldDef(required: true, isEmpty: IsEmptyStrategy.string),
        },
        rules: [],
      );

      final zeroCheck = ump.check({'count': 0, 'name': 'test'});
      expect(zeroCheck['count']!.satisfied, isTrue);

      final nullCheck = ump.check({'count': null, 'name': 'test'});
      expect(nullCheck['count']!.satisfied, isFalse);
    });
  });

  group('Umpire — empty conditions', () {
    test('empty map conditions does not affect evaluation', () {
      final ump = umpire(
        fields: {'email': FieldDef(required: true)},
        rules: [
          enabledWhen('email',
            predicate: (v, c) => c['flag'] != false,
          ),
        ],
      );

      final avail = ump.check({'email': 'test@test.com'});
      expect(avail['email']!.enabled, isTrue);
    });
  });

  group('Umpire — isEmpty strategy type mismatch', () {
    test('non-string value with string isEmpty strategy is empty', () {
      final ump = umpire(
        fields: {'field': FieldDef(required: true, isEmpty: IsEmptyStrategy.string)},
        rules: [],
      );

      final avail = ump.check({'field': 42});
      expect(avail['field']!.satisfied, isFalse);
    });
  });

  group('Umpire — rapid successive check() calls', () {
    test('rapid successive checks produce consistent results', () {
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

      for (int i = 0; i < 10; i++) {
        final avail = ump.check({
          'accountType': i % 2 == 0 ? 'business' : 'personal',
        });
        expect(avail['companyName']!.enabled, i % 2 == 0 ? isTrue : isFalse);
      }
    });
  });

  group('Umpire.play() — edge cases', () {
    test('identical before/after availability produces no fouls', () {
      final ump = umpire(
        fields: {'email': FieldDef(required: true)},
        rules: [],
      );

      final before = ump.check({'email': 'a@b.com'});
      final after = ump.check({'email': 'a@b.com'});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'email': 'a@b.com'},
      );
      expect(fouls, isEmpty);
    });

    test('missing fields in before/after maps are skipped gracefully', () {
      final ump = umpire(
        fields: {
          'email': FieldDef(required: true),
          'name': FieldDef(required: false),
        },
        rules: [],
      );

      final before = ump.check({'email': 'a@b.com'});
      final after = ump.check({'email': 'a@b.com', 'name': 'John'});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'email': 'a@b.com', 'name': 'John'},
      );
      expect(fouls, isEmpty);
    });

    test('missing field in values map is handled gracefully', () {
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

      final before = ump.check({'accountType': 'business', 'companyName': 'ACME'});
      final after = ump.check({'accountType': 'personal'});

      final fouls = ump.play(
        before: before,
        after: after,
        values: {'accountType': 'personal'},
      );
      expect(fouls.where((f) => f.field == 'companyName'), isEmpty);
    });
  });
}
