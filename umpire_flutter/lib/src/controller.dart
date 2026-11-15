import 'package:flutter/foundation.dart';
import 'package:umpire/umpire.dart';

class UmpireController extends ChangeNotifier {
  final Umpire _ump;

  late AvailabilityMap _availability;
  Map<String, dynamic> _values;
  Map<String, dynamic> _conditions;
  List<Foul> _fouls = [];
  AvailabilityMap? _prevAvailability;

  UmpireController({
    required Umpire ump,
    Map<String, dynamic> initialValues = const {},
    Map<String, dynamic> conditions = const {},
  })  : _ump = ump,
        _values = initialValues.isNotEmpty ? initialValues : ump.init(),
        _conditions = conditions {
    _availability = _ump.check(_values, conditions: _conditions);
  }

  AvailabilityMap get availability => _availability;
  Map<String, dynamic> get values => _values;
  List<Foul> get fouls => _fouls;

  bool get isValid {
    if (_fouls.isNotEmpty) return false;
    for (final entry in _availability.entries) {
      final avail = entry.value;
      if (!avail.enabled) continue;
      if (avail.required && !avail.satisfied) return false;
      if (avail.valid == false) return false;
    }
    return true;
  }

  void setValue(String field, dynamic value) {
    _applyUpdate(values: {..._values, field: value});
  }

  void setValues(Map<String, dynamic> values) {
    _applyUpdate(values: {..._values, ...values});
  }

  void setConditions(Map<String, dynamic> conditions) {
    _applyUpdate(conditions: conditions);
  }

  void reset() {
    _applyUpdate(values: _ump.init());
  }

  void _applyUpdate({
    Map<String, dynamic>? values,
    Map<String, dynamic>? conditions,
  }) {
    final previousValues = _values;
    _prevAvailability = _availability;
    if (values != null) _values = values;
    if (conditions != null) _conditions = conditions;
    _availability =
        _ump.check(_values, conditions: _conditions, prev: previousValues);
    _fouls = _ump.play(
      before: _prevAvailability!,
      after: _availability,
      values: _values,
    );
    notifyListeners();
  }
}
