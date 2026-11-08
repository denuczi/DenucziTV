import 'dart:ffi';
import 'dart:io';

import '../domain/stable_release.dart';

Future<UpdateTarget> detectUpdateTarget() async {
  final abi = Abi.current();
  if (Platform.isWindows && abi == Abi.windowsX64) {
    return UpdateTarget.windowsX64;
  }
  if (!Platform.isLinux || abi != Abi.linuxX64) return UpdateTarget.unsupported;
  try {
    return linuxUpdateTarget(await File('/etc/os-release').readAsString());
  } catch (_) {
    return UpdateTarget.unsupported;
  }
}

UpdateTarget linuxUpdateTarget(String osRelease) {
  final values = <String, String>{};
  for (final line in osRelease.split('\n')) {
    final match = RegExp(r'^(ID|ID_LIKE)=(.*)$').firstMatch(line);
    if (match == null) continue;
    values[match.group(1)!] = match
        .group(2)!
        .replaceAll(RegExp('["\']'), '')
        .trim();
  }
  final families = '${values['ID'] ?? ''} ${values['ID_LIKE'] ?? ''}'.split(
    RegExp(r'\s+'),
  );
  return families.any((family) => family == 'debian' || family == 'ubuntu')
      ? UpdateTarget.debianX64
      : UpdateTarget.unsupported;
}
