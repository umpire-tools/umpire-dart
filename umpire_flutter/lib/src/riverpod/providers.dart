import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:umpire/umpire.dart';

import 'notifier.dart';

final umpireProvider =
    StateNotifierProvider.family<UmpireNotifier, UmpireState, Umpire>(
  (ref, ump) => UmpireNotifier(ump),
);
