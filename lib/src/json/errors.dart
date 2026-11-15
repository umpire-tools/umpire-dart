/// Thrown when a JSON schema document is not a valid Umpire v1 document.
class UmpireSchemaException implements Exception {
  final String message;
  UmpireSchemaException(this.message);

  @override
  String toString() => 'UmpireSchemaException: $message';
}
