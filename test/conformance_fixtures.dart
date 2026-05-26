import 'dart:io';

/// Returns the path to the conformance fixtures directory.
///
/// If `UMPIRE_SPEC_CONFORMANCE_DIR` is set, uses that directory directly.
/// Otherwise returns `spec/conformance/` (synced by `mise run spec-sync`).
String resolveConformanceDir() {
  final envDir = Platform.environment['UMPIRE_SPEC_CONFORMANCE_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final indexFile = File('$envDir/index.json');
    if (indexFile.existsSync()) {
      return envDir;
    }
    throw Exception(
      'UMPIRE_SPEC_CONFORMANCE_DIR is set to "$envDir" '
      'but index.json was not found there.',
    );
  }

  return 'spec/conformance';
}
