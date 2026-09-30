import 'dart:convert';
import 'dart:io';

/// Commands are intercepted only in a synthetic child environment. The gate
/// records a PID and public paths, never identity contents or phone tokens.
class RecoveryProcess {
  RecoveryProcess(this.process, this.control) {
    output = process.stdout.transform(utf8.decoder).join();
    errors = process.stderr.transform(utf8.decoder).join();
  }
  final Process process;
  final Directory control;
  late final Future<String> output, errors;
  bool _finished = false;
  static String get dart {
    final override = Platform.environment['DART_EXECUTABLE'];
    if (override != null && override.isNotEmpty) return override;
    final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
    var ancestor = File(Platform.resolvedExecutable).parent;
    // flutter_tester lives below bin/cache/artifacts; standalone Dart lives
    // below bin/cache/dart-sdk. Discover their shared SDK without user paths.
    while (true) {
      for (final relative in [
        dartName,
        'dart-sdk/bin/$dartName',
        'bin/cache/dart-sdk/bin/$dartName',
      ]) {
        final candidate = File('${ancestor.path}/$relative');
        if (candidate.existsSync()) return candidate.path;
      }
      final parent = ancestor.parent;
      if (parent.path == ancestor.path) break;
      ancestor = parent;
    }
    return dartName;
  }

  static Future<RecoveryProcess> start(
    Directory control,
    List<String> args, {
    String? boundary,
  }) async {
    await control.create(recursive: true);
    final bin = Directory('${control.path}/bin');
    await bin.create();
    for (final command in ['chmod', 'sync', 'mv']) {
      final wrapper = File('${bin.path}/$command');
      await wrapper.writeAsString('''#!/bin/bash
set -eu
command=$command
boundary="\${RECOVERY_BOUNDARY:-}"
gate=false
if [ "\$command" = chmod ] && [ "\$boundary" = copy-staged ]; then
  case "\${!#}" in
    */.office-recovery-*/workspace.sqlite)
      /usr/bin/chmod "\$@"
      gate=true
      ;;
  esac
fi
if [ "\$command" = sync ]; then
  count=0
  if [ -f "\$RECOVERY_CONTROL/count" ]; then read -r count < "\$RECOVERY_CONTROL/count"; fi
  count=\$((count + 1))
  echo "\$count" > "\$RECOVERY_CONTROL/count"
  if [ "\$boundary" = before-publish ] && [ "\$count" = 1 ]; then gate=true; fi
  if [ "\$boundary" = after-publish ] && [ "\$count" = 2 ]; then gate=true; fi
fi
if [ "\$command" = mv ] && [ "\$boundary" = race ]; then gate=true; fi
if [ "\$gate" = true ]; then
  echo "\$\$" > "\$RECOVERY_CONTROL/pid"
  : > "\$RECOVERY_CONTROL/ready"
  for ((i=0; i<400; i++)); do
    if [ -f "\$RECOVERY_CONTROL/release" ]; then exec /usr/bin/"\$command" "\$@"; fi
    /usr/bin/sleep 0.05
  done
  exit 124
fi
exec /usr/bin/"\$command" "\$@"
''');
      final chmod = await Process.run('/usr/bin/chmod', ['700', wrapper.path]);
      if (chmod.exitCode != 0) throw StateError('Cannot protect test wrapper.');
    }
    final process = await Process.start(
      dart,
      ['--suppress-analytics', 'run', ...args],
      environment: {
        'PATH':
            '${bin.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        'RECOVERY_CONTROL': control.path,
        'RECOVERY_BOUNDARY': boundary ?? '',
      },
    );
    return RecoveryProcess(process, control);
  }

  Future<void> ready() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!await File('${control.path}/ready').exists()) {
      if (DateTime.now().isAfter(deadline)) {
        await stop();
        throw StateError('Child did not reach recovery gate: ${await errors}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> release() => File('${control.path}/release').writeAsString('go');

  Future<int> finish() async {
    final code = await process.exitCode.timeout(const Duration(seconds: 20));
    _finished = true;
    return code;
  }

  Future<void> stop() async {
    if (_finished) return;
    process.kill(ProcessSignal.sigkill);
    final pidFile = File('${control.path}/pid');
    if (await pidFile.exists()) {
      Process.killPid(
        int.parse(await pidFile.readAsString()),
        ProcessSignal.sigkill,
      );
    }
    await process.exitCode.timeout(const Duration(seconds: 5));
    await Future.wait([output, errors]).timeout(const Duration(seconds: 5));
    _finished = true;
  }
}
