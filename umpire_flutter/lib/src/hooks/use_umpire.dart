import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:umpire/umpire.dart';

class UmpireHookResult {
  final Map<String, dynamic> values;
  final AvailabilityMap availability;
  final List<Foul> fouls;
  final bool isValid;
  final void Function(String field, dynamic value) setValue;
  final void Function(Map<String, dynamic> patch) setValues;
  final void Function(Map<String, dynamic> conditions) setConditions;

  const UmpireHookResult({
    required this.values,
    required this.availability,
    required this.fouls,
    required this.isValid,
    required this.setValue,
    required this.setValues,
    required this.setConditions,
  });
}

T? usePrevious<T>(T current) {
  final ref = useRef<T?>(null);
  useEffect(() {
    Future.microtask(() => ref.value = current);
    return null;
  }, [current]);
  return ref.value;
}

UmpireHookResult useUmpire(
  Umpire ump, {
  Map<String, dynamic> initialValues = const {},
  Map<String, dynamic> conditions = const {},
}) {
  final values = useState(initialValues);
  final conds = useState(conditions);

  final prevValues = usePrevious(values.value);

  final availability = useMemoized(
    () => ump.check(values.value, conditions: conds.value, prev: prevValues),
    [values.value, conds.value],
  );

  final prevAvailability = usePrevious(availability);

  final fouls = useMemoized(
    () => prevAvailability != null
        ? ump.play(
            before: prevAvailability,
            after: availability,
            values: values.value,
          )
        : <Foul>[],
    [availability],
  );

  final isValid = fouls.isEmpty &&
      availability.values.every((a) {
        if (!a.enabled) return true;
        if (a.required && !a.satisfied) return false;
        if (a.valid == false) return false;
        return true;
      });

  return UmpireHookResult(
    values: values.value,
    availability: availability,
    fouls: fouls,
    isValid: isValid,
    setValue: (field, value) =>
        values.value = {...values.value, field: value},
    setValues: (patch) =>
        values.value = {...values.value, ...patch},
    setConditions: (c) => conds.value = c,
  );
}
