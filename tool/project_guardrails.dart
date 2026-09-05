import 'dart:convert';
import 'dart:io';

const expectedOrigin = 'https://github.com/gr-linkk/vortice-app-next';
const expectedSupabaseUrl = 'https://hkjpojobdbbtjkhaudki.supabase.co';
const expectedProjectRef = 'hkjpojobdbbtjkhaudki';
const baselineMigration = '20260905000000_vortice_next_baseline.sql';
const retiredMockPassword =
    'vortice'
    '2026';
const originalProjectRef =
    'ymqtjvvy'
    'dobuwqicrokq';

final migrationName = RegExp(r'^(\d{14})_[a-z0-9_]+\.sql$');
final jwtPattern = RegExp(
  r'eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}',
);
final secretKeyPattern = RegExp(r'sb_secret_[a-zA-Z0-9_-]+');

Never _fail(String message) => throw StateError(message);

String normalizeUrl(String value) => value
    .trim()
    .replaceAll('\\', '/')
    .replaceFirst(RegExp(r'\.git$'), '')
    .replaceFirst(RegExp(r'/$'), '')
    .toLowerCase();

ProcessResult runGit(List<String> arguments, {bool allowFailure = false}) {
  final result = Process.runSync(
    'git',
    arguments,
    runInShell: Platform.isWindows,
  );
  if (!allowFailure && result.exitCode != 0) {
    _fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

List<String> lines(Object value) => value
    .toString()
    .split(RegExp(r'\r?\n'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

void checkRepositoryIdentity() {
  final remotes = lines(runGit(['remote']).stdout);
  if (remotes.length != 1 || remotes.single != 'origin') {
    _fail('Expected exactly one Git remote named origin; found $remotes');
  }
  final origin = runGit(['remote', 'get-url', 'origin']).stdout.toString();
  if (normalizeUrl(origin) != expectedOrigin) {
    _fail('Unexpected origin remote: ${origin.trim()}');
  }
}

List<File> migrationFiles() {
  final directory = Directory('supabase/migrations');
  if (!directory.existsSync()) _fail('Missing supabase/migrations directory.');
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void checkMigrationChain() {
  final files = migrationFiles();
  if (files.isEmpty) _fail('The deployable migration chain is empty.');
  final names = files.map((file) => file.uri.pathSegments.last).toList();
  if (names.first != baselineMigration) {
    _fail('The deployable chain must start with $baselineMigration.');
  }

  final timestamps = <String>{};
  for (final name in names) {
    final match = migrationName.firstMatch(name);
    if (match == null) _fail('Malformed deployable migration filename: $name');
    if (!timestamps.add(match.group(1)!)) {
      _fail('Duplicate deployable migration timestamp: ${match.group(1)}');
    }
  }
}

List<String> migrationNamesAt(String ref) {
  return lines(
        runGit([
          'ls-tree',
          '-r',
          '--name-only',
          ref,
          '--',
          'supabase/migrations',
        ]).stdout,
      )
      .map((path) => path.split('/').last)
      .where((name) => name.endsWith('.sql'))
      .toList();
}

void checkMigrationDiff(String baseRef) {
  final diff = lines(
    runGit([
      'diff',
      '--ignore-cr-at-eol',
      '--ignore-space-at-eol',
      '--name-status',
      baseRef,
      '--',
      'supabase/migrations',
    ]).stdout,
  );
  final added = <String>[];
  for (final row in diff) {
    final fields = row.split(RegExp(r'\s+'));
    final path = fields.last;
    if (fields.first == 'M') {
      final normalizedDiff = runGit([
        'diff',
        '--quiet',
        '--ignore-cr-at-eol',
        '--ignore-space-at-eol',
        baseRef,
        '--',
        path,
      ], allowFailure: true);
      if (normalizedDiff.exitCode == 0) continue;
    }
    if (fields.first != 'A') {
      _fail('Deployed migrations are immutable; disallowed change: $row');
    }
    added.add(path.split('/').last);
  }

  final baseNames = migrationNamesAt(baseRef);
  final baseTimestamps = baseNames
      .map(migrationName.firstMatch)
      .whereType<RegExpMatch>()
      .map((match) => match.group(1)!)
      .toList();
  if (baseTimestamps.isEmpty) return;
  baseTimestamps.sort();
  final latestBase = baseTimestamps.last;
  for (final name in added) {
    final match = migrationName.firstMatch(name);
    if (match == null) _fail('Malformed new migration filename: $name');
    if (match.group(1)!.compareTo(latestBase) <= 0) {
      _fail(
        'New migration $name is not later than deployed migration timestamp $latestBase.',
      );
    }
  }
}

void checkLocalPathsAreIgnored() {
  for (final path in [
    'config/vortice-next.local.json',
    'outputs/guardrail-probe.txt',
    'work/guardrail-probe.txt',
  ]) {
    final result = runGit([
      'check-ignore',
      '-q',
      '--',
      path,
    ], allowFailure: true);
    if (result.exitCode != 0) _fail('Local-only path is not ignored: $path');
  }
}

void checkConfigAndLinkedProject() {
  final example = File('config/vortice-next.example.json');
  if (!example.existsSync()) _fail('Missing tracked Supabase config example.');
  final value = jsonDecode(example.readAsStringSync()) as Map<String, dynamic>;
  if (value['SUPABASE_URL'] != expectedSupabaseUrl) {
    _fail(
      'Config example must target only the dedicated Vortice Next project.',
    );
  }
  if (value['SUPABASE_ANON_KEY'] != 'YOUR-PUBLISHABLE-OR-ANON-KEY') {
    _fail('Config example must contain only the public-key placeholder.');
  }

  final linkedRef = File('supabase/.temp/project-ref');
  if (linkedRef.existsSync() &&
      linkedRef.readAsStringSync().trim() != expectedProjectRef) {
    _fail('Local Supabase link targets an unauthorized project ref.');
  }
}

void checkTrackedSecrets() {
  final tracked = runGit(['ls-files', '-z']).stdout.toString().split('\u0000');
  const textExtensions = {
    '.dart',
    '.md',
    '.sql',
    '.yaml',
    '.yml',
    '.json',
    '.toml',
    '.js',
    '.ps1',
    '.sh',
    '.kts',
    '.gradle',
    '.xml',
    '.plist',
    '.xcconfig',
    '.properties',
    '.swift',
    '.kt',
    '.h',
    '.cc',
    '.cmake',
    '.txt',
  };
  for (final path in tracked.where((path) => path.isNotEmpty)) {
    final extension = path.contains('.')
        ? '.${path.split('.').last.toLowerCase()}'
        : '';
    if (!textExtensions.contains(extension)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final content = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    if (content.contains(retiredMockPassword) ||
        content.contains(originalProjectRef) ||
        jwtPattern.hasMatch(content) ||
        secretKeyPattern.hasMatch(content)) {
      _fail(
        'Credential-like or original-project material found in tracked file: $path',
      );
    }
  }
}

void main(List<String> arguments) {
  String? baseRef;
  if (arguments.isNotEmpty) {
    if (arguments.length != 2 || arguments.first != '--base-ref') {
      _fail(
        'Usage: dart run tool/project_guardrails.dart [--base-ref <git-ref>]',
      );
    }
    baseRef = arguments[1];
  }

  checkRepositoryIdentity();
  checkMigrationChain();
  if (baseRef != null) checkMigrationDiff(baseRef);
  checkLocalPathsAreIgnored();
  checkConfigAndLinkedProject();
  checkTrackedSecrets();
  stdout.writeln('Project guardrails passed.');
}
