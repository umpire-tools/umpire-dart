import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _defaultVersion = '1.0.0';
const _registryUrl = 'https://registry.npmjs.org/@umpire/json';

Future<String> resolveConformanceDir() async {
  final envDir = Platform.environment['UMPIRE_JSON_CONFORMANCE_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final indexFile = File('$envDir/index.json');
    if (indexFile.existsSync()) {
      return envDir;
    }
    throw Exception(
      'UMPIRE_JSON_CONFORMANCE_DIR is set to "$envDir" '
      'but index.json was not found there.',
    );
  }

  final version =
      Platform.environment['UMPIRE_JSON_VERSION'] ?? _defaultVersion;
  final cacheRoot = '${Directory.current.path}/.dart_tool/umpire-json';
  final conformanceDir = '$cacheRoot/$version/conformance';

  final cachedIndex = File('$conformanceDir/index.json');
  if (cachedIndex.existsSync()) {
    return conformanceDir;
  }

  await _downloadAndCache(version, cacheRoot, conformanceDir);
  return conformanceDir;
}

Future<void> _downloadAndCache(
    String version, String cacheRoot, String conformanceDir) async {
  final client = http.Client();
  try {
    final metadataResp = await client.get(Uri.parse(_registryUrl));
    final metadata = jsonDecode(metadataResp.body) as Map<String, dynamic>;
    final versions = metadata['versions'] as Map<String, dynamic>;
    final versionData = versions[version];
    if (versionData == null) {
      throw Exception(
        'Version $version not found in @umpire/json registry. '
        'Available versions: ${versions.keys.join(', ')}',
      );
    }

    final dist = versionData['dist'] as Map<String, dynamic>;
    final tarballUrl = dist['tarball'] as String;

    final tarballResp = await client.get(Uri.parse(tarballUrl));
    final tarballBytes = tarballResp.bodyBytes;

    final tmpDir = Directory.systemTemp.createTempSync('umpire-json-');
    try {
      final tarballPath = '${tmpDir.path}/package.tgz';
      File(tarballPath).writeAsBytesSync(tarballBytes);

      final extractDir = '${tmpDir.path}/extract';
      Directory(extractDir).createSync();

      final tarResult = Process.runSync('tar', [
        '-xzf',
        tarballPath,
        '-C',
        extractDir,
        'package/conformance/',
      ]);

      if (tarResult.exitCode != 0) {
        throw Exception(
          'Failed to extract tarball (exit ${tarResult.exitCode}): '
          '${tarResult.stderr}',
        );
      }

      final extractedConformance =
          Directory('$extractDir/package/conformance');
      if (!extractedConformance.existsSync()) {
        throw Exception(
          'Extracted tarball but package/conformance/ was not found',
        );
      }

      final cacheDir = Directory(conformanceDir);
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
      cacheDir.parent.createSync(recursive: true);

      for (final entry in extractedConformance.listSync()) {
        final name = entry.uri.pathSegments.last;
        final dest = '${cacheDir.path}/$name';
        if (entry is Directory) {
          _copyDirectorySync(entry.path, dest);
        } else if (entry is File) {
          entry.copySync(dest);
        }
      }
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  } finally {
    client.close();
  }
}

void _copyDirectorySync(String src, String dest) {
  final srcDir = Directory(src);
  final destDir = Directory(dest);
  destDir.createSync(recursive: true);

  for (final entry in srcDir.listSync()) {
    final name = entry.uri.pathSegments.last;
    final destPath = '${destDir.path}/$name';
    if (entry is Directory) {
      _copyDirectorySync(entry.path, destPath);
    } else if (entry is File) {
      entry.copySync(destPath);
    }
  }
}
