import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:umpire/umpire.dart';

class UmpireState {
  final Map<String, dynamic> values;
  final AvailabilityMap availability;
  final List<Foul> fouls;
  final Map<String, dynamic> conditions;

  const UmpireState({
    required this.values,
    required this.availability,
    required this.fouls,
    this.conditions = const {},
  });

  bool get isValid {
    if (fouls.isNotEmpty) return false;
    for (final entry in availability.entries) {
      final avail = entry.value;
      if (!avail.enabled) continue;
      if (avail.required && !avail.satisfied) return false;
      if (avail.valid == false) return false;
    }
    return true;
  }
}

class UmpireNotifier extends StateNotifier<UmpireState> {
  final Umpire _ump;

  UmpireNotifier(Umpire ump, {Map<String, dynamic> conditions = const {}})
      : _ump = ump,
        super(UmpireState(
          values: ump.init(),
          availability: ump.check(ump.init(), conditions: conditions),
          fouls: const [],
          conditions: conditions,
        ));

  void setValue(String field, dynamic value) {
    _applyUpdate(values: {...state.values, field: value});
  }

  void setValues(Map<String, dynamic> patch) {
    _applyUpdate(values: {...state.values, ...patch});
  }

  void setConditions(Map<String, dynamic> conditions) {
    _applyUpdate(conditions: conditions);
  }

  void _applyUpdate({
    Map<String, dynamic>? values,
    Map<String, dynamic>? conditions,
  }) {
    final prevAvailability = state.availability;
    final nextValues = values ?? state.values;
    final nextConditions = conditions ?? state.conditions;
    final nextAvailability = _ump.check(nextValues, conditions: nextConditions);
    final fouls = _ump.play(
      before: prevAvailability,
      after: nextAvailability,
      values: nextValues,
    );
    state = UmpireState(
      values: nextValues,
      availability: nextAvailability,
      fouls: fouls,
      conditions: nextConditions,
    );
  }
}
