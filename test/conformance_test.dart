import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:umpire/umpire.dart' hide anyOf;

import 'conformance_fixtures.dart';

void main() {
  group('conformance fixtures', () {
    String? conformanceDir;
    List<Map<String, dynamic>> allFixtures = [];
    List<Map<String, dynamic>> allFailures = [];

    setUpAll(() async {
      conformanceDir = await resolveConformanceDir();
      final indexFile = File('$conformanceDir/index.json');
      final index =
          jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;

     final fixtureEntries = index['fixtures'] as List<dynamic>? ?? [];
        for (final entry in fixtureEntries) {
          final relPath = entry is String ? entry : (entry as Map<String, dynamic>)['path'] as String;
          final fixturePath = '$conformanceDir/$relPath';
          final data =
              jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
          allFixtures.add(data);
        }

        final failureEntries = index['failures'] as List<dynamic>? ?? [];
        for (final entry in failureEntries) {
          final relPath = entry is String ? entry : (entry as Map<String, dynamic>)['path'] as String;
          final failurePath = '$conformanceDir/$relPath';
          final data =
              jsonDecode(File(failurePath).readAsStringSync()) as Map<String, dynamic>;
          allFailures.add(data);
        }
    });

    test('fixtures are loaded', () {
      expect(allFixtures, isNotEmpty);
      expect(allFailures, isNotEmpty);
    });

    test('all conformance fixtures pass', () {
      for (var fi = 0; fi < allFixtures.length; fi++) {
        final fixtureData = allFixtures[fi];
        final schema =
            UmpireSchema.fromJson(fixtureData['schema'] as Map<String, dynamic>);
        final ump = schema.build();

        final cases = fixtureData['cases'] as List<dynamic>? ?? const [];
        if (cases.isEmpty) {
          fail('fixture[$fi] has no cases');
        }
        for (var ci = 0; ci < cases.length; ci++) {
          final c = cases[ci] as Map<String, dynamic>;
          final values = c['values'] as Map<String, dynamic>? ?? {};
          final conditions = c['conditions'] as Map<String, dynamic>? ?? {};
          final prev = c['prev'] as Map<String, dynamic>?;

          final availability =
              ump.check(values, conditions: conditions, prev: prev);

          final actualMap = <String, Map<String, dynamic>>{};
          for (final entry in availability.entries) {
            actualMap[entry.key] = _availabilityToMap(entry.value);
          }

          final expected = c['expectedAvailability'] as Map<String, dynamic>;
          _compareAvailability(
            expected,
            actualMap,
            'fixture[$fi] case[$ci]',
          );
        }
      }
    });

    test('all failure fixtures throw as expected', () {
      for (var fi = 0; fi < allFailures.length; fi++) {
        final failureData = allFailures[fi];
        final failures = failureData['failures'] as List<dynamic>;

        for (var i = 0; i < failures.length; i++) {
          final f = failures[i] as Map<String, dynamic>;
          final phase = f['phase'] as String;

          final where = 'Failure fixture[$fi] case[$i] {${f['id']}}';

          if (phase == 'validate') {
            _expectThrowsWithMessage(
              () => UmpireSchema.fromJson(
                  f['schema'] as Map<String, dynamic>),
              f['errorIncludes'] as String?,
              where,
              matcher: isA<UmpireSchemaException>(),
            );
          } else if (phase == 'evaluate') {
            final schema = UmpireSchema.fromJson(
                f['schema'] as Map<String, dynamic>);
            final ump = schema.build();
            final values = f['values'] as Map<String, dynamic>? ?? {};
            final conditions =
                f['conditions'] as Map<String, dynamic>? ?? {};

            _expectThrowsWithMessage(
              () => ump.check(values, conditions: conditions),
              f['errorIncludes'] as String?,
              where,
              matcher: anyOf(isA<Exception>(), isA<ArgumentError>()),
            );
          } else {
            fail('$where: unknown failure phase "$phase"');
          }
        }
      }
    });
  });

  group('spec sync', () {
    final overrideDir = Platform.environment['UMPIRE_SPEC_CONFORMANCE_DIR'];

    test(
      'spec/ is synced at the version pinned in mise.toml',
      () {
        final syncedAt = File('spec/.synced-at-version');
        if (!syncedAt.existsSync()) {
          fail('spec/.synced-at-version is missing; run `mise run spec-sync`');
        }
        expect(
          syncedAt.readAsStringSync().trim(),
          _pinnedSpecVersion(),
          reason: 'spec/ fixtures are stale; run `mise run spec-sync`',
        );
      },
      skip: overrideDir != null && overrideDir.isNotEmpty
          ? 'UMPIRE_SPEC_CONFORMANCE_DIR points at an external spec checkout'
          : null,
    );
  });
}

/// Reads `UMPIRE_SPEC_VERSION` out of `mise.toml`.
String _pinnedSpecVersion() {
  final toml = File('mise.toml').readAsStringSync();
  final match =
      RegExp(r'^UMPIRE_SPEC_VERSION\s*=\s*"([^"]+)"', multiLine: true)
          .firstMatch(toml);
  if (match == null) {
    fail('mise.toml has no UMPIRE_SPEC_VERSION entry');
  }
  return match.group(1)!;
}

void _compareAvailability(
  Map<String, dynamic> expected,
  Map<String, dynamic> actual,
  String context,
) {
  final extraFields = actual.keys.toSet().difference(expected.keys.toSet());
  expect(
    extraFields,
    isEmpty,
    reason: '$context: fields missing from expectedAvailability $extraFields',
  );

  for (final fieldEntry in expected.entries) {
    final field = fieldEntry.key;
    final expectedField = fieldEntry.value as Map<String, dynamic>;
    final actualField = actual[field];

    if (actualField == null) {
      fail('$context, field "$field": missing in actual output');
    }

    for (final propEntry in expectedField.entries) {
      final prop = propEntry.key;
      final expectedValue = propEntry.value;
      final actualValue = actualField[prop];

      if (expectedValue is List) {
        expect(
          actualValue,
          equals(expectedValue),
          reason:
              '$context, field "$field.$prop": '
              'expected $expectedValue but got $actualValue',
        );
      } else {
        expect(
          actualValue,
          expectedValue,
          reason:
              '$context, field "$field.$prop": '
              'expected $expectedValue but got $actualValue',
        );
      }
    }

    expect(
      actualField.keys.toSet().difference(expectedField.keys.toSet()),
      isEmpty,
      reason: '$context, field "$field": unexpected status members',
    );
  }
}

/// Asserts that [body] throws, that the thrown object matches [matcher] when
/// one is given, and that the error message contains [errorIncludes] when the
/// fixture pins one.
void _expectThrowsWithMessage(
  void Function() body,
  String? errorIncludes,
  String context, {
  Matcher? matcher,
}) {
  Object? thrown;
  try {
    body();
  } catch (error) {
    thrown = error;
  }

  expect(thrown, isNotNull, reason: '$context: expected a thrown error');

  if (matcher != null) {
    expect(thrown, matcher, reason: '$context: unexpected error type');
  }

  if (errorIncludes != null) {
    expect(thrown.toString(), contains(errorIncludes),
        reason: '$context: error message must include "$errorIncludes"');
  }
}

Map<String, dynamic> _availabilityToMap(FieldAvailability a) {
  final m = <String, dynamic>{
    'enabled': a.enabled,
    'fair': a.fair,
    'required': a.required,
    'reason': a.reason,
    'reasons': a.reasons,
    'satisfied': a.satisfied,
  };
  if (a.valid != null) {
    m['valid'] = a.valid;
  }
  if (a.error != null) {
    m['error'] = a.error;
  }
  return m;
}
