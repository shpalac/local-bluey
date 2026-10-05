import 'dart:convert';
import 'dart:io';

/// Minimal CycloneDX 1.6 SBOM from pubspec.lock (#155). No external
/// binary to pin; package names+versions come from the lockfile.
void main(List<String> args) {
  final out = args.isEmpty ? 'sbom.json' : args.first;
  final lock = File('pubspec.lock').readAsLinesSync();
  final packages = <Map<String, dynamic>>[];
  String? name;
  String? version;
  void flush() {
    if (name != null && version != null) {
      packages.add({
        'type': 'library',
        'bom-ref': 'pkg:pub/$name@$version',
        'name': name,
        'version': version,
        'purl': 'pkg:pub/$name@$version',
      });
    }
  }

  var inPackages = false;
  for (final line in lock) {
    if (line.startsWith('packages:')) {
      inPackages = true;
      continue;
    }
    if (!inPackages) continue;
    if (!line.startsWith(' ')) break;
    final dep = RegExp(r'^ {2}(\S+):$').firstMatch(line);
    if (dep != null) {
      flush();
      name = dep.group(1);
      version = null;
      continue;
    }
    final ver = RegExp(r'^\s+version: "([^"]+)"').firstMatch(line);
    if (ver != null) version = ver.group(1);
  }
  flush();

  final sbom = {
    r'$schema': 'http://cyclonedx.org/schema/bom-1.6.schema.json',
    'bomFormat': 'CycloneDX',
    'specVersion': '1.6',
    'version': 1,
    'metadata': {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'component': {
        'type': 'application',
        'name': 'local-bluey',
        'bom-ref': 'pkg:pub/local-bluey',
      },
    },
    'components': packages,
  };
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sbom));
  stdout.writeln('SBOM: ${packages.length} packages -> $out');
}
