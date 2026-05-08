import 'dart:async';

class ConditionProvider {
  final FutureOr<dynamic> Function()? resolver;
  final dynamic value;

  ConditionProvider.value(this.value) : resolver = null;
  ConditionProvider.async(this.resolver) : value = null;
}
