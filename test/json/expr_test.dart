import 'package:test/test.dart';
import 'package:umpire/src/json/expr.dart';

void main() {
  final fieldNames = {'email', 'planId', 'accountType', 'status'};

  group('compileExpr - condition ops', () {
    test('cond: returns true when condition is true', () {
      final pred = compileExpr(
        {'op': 'cond', 'condition': 'isAdmin'},
        fieldNames: fieldNames,
      );
      expect(pred({}, {'isAdmin': true}), isTrue);
      expect(pred({}, {'isAdmin': false}), isFalse);
      expect(() => pred({}, {}), throwsArgumentError);
    });

    test('condEq: returns true when condition equals value', () {
      final pred = compileExpr(
        {'op': 'condEq', 'condition': 'tier', 'value': 'pro'},
        fieldNames: fieldNames,
      );
      expect(pred({}, {'tier': 'pro'}), isTrue);
      expect(pred({}, {'tier': 'free'}), isFalse);
      expect(pred({}, {'tier': 'team'}), isFalse);
    });

    test('condIn: returns true when condition value is in static list', () {
      final pred = compileExpr(
        {'op': 'condIn', 'condition': 'tier', 'values': ['pro', 'team']},
        fieldNames: fieldNames,
      );
      expect(pred({}, {'tier': 'pro'}), isTrue);
      expect(pred({}, {'tier': 'team'}), isTrue);
      expect(pred({}, {'tier': 'free'}), isFalse);
      expect(pred({}, {'tier': 'basic'}), isFalse);
    });

    test('fieldInCond: returns true when field value is in condition array',
        () {
      final pred = compileExpr(
        {'op': 'fieldInCond', 'field': 'planId', 'condition': 'validPlans'},
        fieldNames: fieldNames,
      );
      expect(
        pred({'planId': 'pro'}, {'validPlans': ['pro', 'team']}),
        isTrue,
      );
      expect(
        pred({'planId': 'free'}, {'validPlans': ['pro', 'team']}),
        isFalse,
      );
    });

    test('fieldInCond handles null/missing condition safely', () {
      final pred = compileExpr(
        {'op': 'fieldInCond', 'field': 'planId', 'condition': 'validPlans'},
        fieldNames: fieldNames,
      );
      expect(() => pred({'planId': 'pro'}, {}), throwsArgumentError);
      expect(
          pred({'planId': 'pro'}, {'validPlans': 'not-a-list'}), isFalse);
    });

    test('fieldInCond does not coerce scalars and never reads an array value',
        () {
      final pred = compileExpr(
        {'op': 'fieldInCond', 'field': 'planId', 'condition': 'validPlans'},
        fieldNames: fieldNames,
      );

      expect(pred({'planId': true}, {'validPlans': [1]}), isFalse);
      expect(pred({'planId': 1}, {'validPlans': [true]}), isFalse);
      expect(pred({'planId': '22'}, {'validPlans': [22]}), isFalse);
      expect(pred({'planId': 22}, {'validPlans': [22.0]}), isTrue);
      expect(pred({'planId': [1]}, {'validPlans': [1]}), isFalse);
    });

    test('condIn vs fieldInCond distinction', () {
      final condInPred = compileExpr(
        {'op': 'condIn', 'condition': 'tier', 'values': ['pro', 'team']},
        fieldNames: fieldNames,
      );
      expect(condInPred({}, {'tier': 'pro'}), isTrue);

      final fieldInCondPred = compileExpr(
        {'op': 'fieldInCond', 'field': 'planId', 'condition': 'validPlans'},
        fieldNames: fieldNames,
      );
      expect(
        fieldInCondPred({'planId': 'pro'}, {'validPlans': ['pro', 'team']}),
        isTrue,
      );
    });
  });

  group('compileExpr - field-level ops', () {
    test('eq: returns true when field equals value', () {
      final pred = compileExpr(
        {'op': 'eq', 'field': 'accountType', 'value': 'business'},
        fieldNames: fieldNames,
      );
      expect(pred({'accountType': 'business'}, {}), isTrue);
      expect(pred({'accountType': 'personal'}, {}), isFalse);
    });

    test('neq: returns true when field does not equal value', () {
      final pred = compileExpr(
        {'op': 'neq', 'field': 'accountType', 'value': 'business'},
        fieldNames: fieldNames,
      );
      expect(pred({'accountType': 'personal'}, {}), isTrue);
      expect(pred({'accountType': 'business'}, {}), isFalse);
    });

    test('truthy: returns true for truthy values', () {
      final pred = compileExpr(
        {'op': 'truthy', 'field': 'status'},
        fieldNames: fieldNames,
      );
      expect(pred({'status': 'active'}, {}), isTrue);
      expect(pred({'status': true}, {}), isTrue);
      expect(pred({'status': 1}, {}), isTrue);
      expect(pred({'status': ''}, {}), isFalse);
      expect(pred({'status': 0}, {}), isFalse);
      expect(pred({'status': false}, {}), isFalse);
      expect(pred({'status': null}, {}), isFalse);
      expect(pred({}, {}), isFalse);
    });

    test('falsy: returns true for falsy values', () {
      final pred = compileExpr(
        {'op': 'falsy', 'field': 'status'},
        fieldNames: fieldNames,
      );
      expect(pred({'status': ''}, {}), isTrue);
      expect(pred({'status': null}, {}), isTrue);
      expect(pred({'status': 0}, {}), isTrue);
      expect(pred({'status': 'active'}, {}), isFalse);
      expect(pred({'status': true}, {}), isFalse);
    });

    test('and: returns true when all sub-expressions pass', () {
      final pred = compileExpr({
        'op': 'and',
        'exprs': [
          {'op': 'truthy', 'field': 'email'},
          {'op': 'truthy', 'field': 'planId'},
        ],
      }, fieldNames: fieldNames);

      expect(pred({'email': 'a@b.com', 'planId': 'pro'}, {}), isTrue);
      expect(pred({'email': '', 'planId': 'pro'}, {}), isFalse);
      expect(pred({'email': 'a@b.com', 'planId': ''}, {}), isFalse);
    });

    test('or: returns true when any sub-expression passes', () {
      final pred = compileExpr({
        'op': 'or',
        'exprs': [
          {'op': 'truthy', 'field': 'email'},
          {'op': 'truthy', 'field': 'planId'},
        ],
      }, fieldNames: fieldNames);

      expect(pred({'email': 'a@b.com', 'planId': ''}, {}), isTrue);
      expect(pred({'email': '', 'planId': 'pro'}, {}), isTrue);
      expect(pred({'email': '', 'planId': ''}, {}), isFalse);
    });

    test('not: negates sub-expression', () {
      final pred = compileExpr({
        'op': 'not',
        'expr': {'op': 'truthy', 'field': 'email'},
      }, fieldNames: fieldNames);

      expect(pred({'email': ''}, {}), isTrue);
      expect(pred({'email': 'a@b.com'}, {}), isFalse);
    });
  });

  group('compileExpr - check ops', () {
    test('email check returns true for valid email', () {
      final pred = compileExpr({
        'op': 'check',
        'field': 'email',
        'check': {'op': 'email'},
      }, fieldNames: fieldNames);

      expect(pred({'email': 'user@test.com'}, {}), isTrue);
      expect(pred({'email': 'not-an-email'}, {}), isFalse);
      expect(pred({'email': ''}, {}), isFalse);
      expect(pred({'email': null}, {}), isFalse);
    });

    test('minLength check returns true when length >= value', () {
      final pred = compileExpr({
        'op': 'check',
        'field': 'planId',
        'check': {'op': 'minLength', 'value': 3},
      }, fieldNames: fieldNames);

      expect(pred({'planId': 'pro'}, {}), isTrue);
      expect(pred({'planId': 'ab'}, {}), isFalse);
    });

    test('min, max, and length checks ignore the min/max parameter aliases',
        () {
      for (final check in [
        {'op': 'minLength', 'min': 3},
        {'op': 'maxLength', 'max': 3},
        {'op': 'min', 'min': 3},
        {'op': 'max', 'max': 3},
      ]) {
        expect(
          () => compileExpr({
            'op': 'check',
            'field': 'planId',
            'check': check,
          }, fieldNames: fieldNames),
          throwsArgumentError,
          reason: 'check $check must require "value"',
        );
      }
    });

    test('range check reads its own min and max parameters', () {
      final pred = compileExpr({
        'op': 'check',
        'field': 'planId',
        'check': {'op': 'range', 'min': 2, 'max': 4},
      }, fieldNames: {'planId'});

      expect(pred({'planId': 1}, {}), isFalse);
      expect(pred({'planId': 3}, {}), isTrue);
      expect(pred({'planId': 9}, {}), isFalse);
    });

    test('matches check with regex pattern', () {
      final pred = compileExpr({
        'op': 'check',
        'field': 'planId',
        'check': {'op': 'matches', 'pattern': r'^[a-z]+$'},
      }, fieldNames: fieldNames);

      expect(pred({'planId': 'pro'}, {}), isTrue);
      expect(pred({'planId': 'Pro'}, {}), isFalse);
      expect(pred({'planId': '123'}, {}), isFalse);
    });
  });

  group('compileExpr - error cases', () {
    test('throws on unknown op', () {
      expect(
        () => compileExpr({'op': 'unknownOp'}, fieldNames: fieldNames),
        throwsArgumentError,
      );
    });

    test('throws on unknown field reference in eq', () {
      expect(
        () => compileExpr(
          {'op': 'eq', 'field': 'nonexistent', 'value': 'x'},
          fieldNames: fieldNames,
        ),
        throwsArgumentError,
      );
    });

    test('throws on unknown field reference in truthy', () {
      expect(
        () => compileExpr(
          {'op': 'truthy', 'field': 'nonexistent'},
          fieldNames: fieldNames,
        ),
        throwsArgumentError,
      );
    });

    test('throws on unknown field reference in fieldInCond', () {
      expect(
        () => compileExpr(
          {'op': 'fieldInCond', 'field': 'nonexistent', 'condition': 'x'},
          fieldNames: fieldNames,
        ),
        throwsArgumentError,
      );
    });

    test('throws on missing op field', () {
      expect(
        () => compileExpr({}, fieldNames: fieldNames),
        throwsArgumentError,
      );
    });

    test('throws on excessive nesting depth', () {
      Map<String, dynamic> deep = {'op': 'truthy', 'field': 'email'};
      for (int i = 0; i < 60; i++) {
        deep = {'op': 'not', 'expr': deep};
      }
      expect(
        () => compileExpr(deep, fieldNames: fieldNames),
        throwsArgumentError,
      );
    });
  });
}
