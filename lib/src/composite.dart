import 'rules/rule.dart';

/// Combines multiple rule evaluation results using AND or OR semantics.
RuleEvaluation combineCompositeResults(
  String constraint,
  String mode,
  List<RuleEvaluation> results,
) {
  bool passed = mode == 'and';

  for (final result in results) {
    final currentPassed = constraint == 'fair'
        ? result.fair != false
        : result.enabled;

    if (mode == 'and') {
      if (!currentPassed) {
        passed = false;
        break;
      }
    } else {
      if (currentPassed) {
        passed = true;
        break;
      }
    }
  }

  if (passed) {
    return constraint == 'fair'
        ? const RuleEvaluation(enabled: true, fair: true, reason: null)
        : const RuleEvaluation(enabled: true, reason: null);
  }

  final reasons = <String>[];
  for (final result in results) {
    _collectReasons(result, reasons);
  }

  return constraint == 'fair'
      ? RuleEvaluation(
          enabled: true,
          fair: false,
          reason: reasons.isEmpty ? null : reasons.first,
          reasons: reasons.isEmpty ? null : reasons,
        )
      : RuleEvaluation(
          enabled: false,
          reason: reasons.isEmpty ? null : reasons.first,
          reasons: reasons.isEmpty ? null : reasons,
        );
}

void _collectReasons(RuleEvaluation result, List<String> reasons) {
  if (result.reasons != null && result.reasons!.isNotEmpty) {
    reasons.addAll(result.reasons!);
    return;
  }
  if (result.reason != null) {
    reasons.add(result.reason!);
  }
}
