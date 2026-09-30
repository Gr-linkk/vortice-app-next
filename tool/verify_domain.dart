// Run with plain `dart run tool/verify_domain.dart`: no Flutter engine, service,
// credentials or package runtime is needed by the maintenance policy itself.
import 'dart:io';

import 'package:vortice_app/domain/checklist.dart';
import 'package:vortice_app/domain/membership_access.dart';
import 'package:vortice_app/domain/report_command.dart';
import 'package:vortice_app/domain/work_report.dart';

void check(bool condition, String contract) {
  if (!condition) throw StateError(contract);
}

void main() {
  // Keep future additions honest as well as the files compiled above.
  for (final file in Directory(
    'lib/domain',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    for (final match in RegExp(
      r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
    ).allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;
      check(
        !uri.startsWith('package:') &&
            !uri.startsWith('dart:ui') &&
            (uri.startsWith('dart:') || !uri.contains('..')),
        'Domain must not depend on UI, plugins or external adapters: ${file.path}: $uri',
      );
    }
  }

  const item = {
    'id': 'pressure',
    'requires_photo': true,
    'definition': {
      'input_type': 'number',
      'min': 10,
      'max': 20,
      'allow_na': false,
    },
  };
  final answers = <String, dynamic>{
    'pressure': <String, dynamic>{
      'result': 'pass',
      'note': '15',
      'photo_path': 'proof',
    },
  };
  WorkReportProgress progress(String meter, List<String> evidence) =>
      WorkReportProgress(
        diagnosis: 'Leaking seal',
        repair: 'Replaced and pressure tested',
        items: const [item],
        answers: answers,
        evidence: evidence,
        meter: meter,
        meterRequired: true,
        startingMeter: 100,
      );
  check(
    progress('101', ['proof']).complete,
    'A complete report can be submitted',
  );
  check(
    !progress('99', ['proof']).complete,
    'A backwards meter cannot be submitted',
  );
  check(
    !progress('NaN', ['proof']).complete,
    'An invalid meter cannot be submitted',
  );
  check(
    !progress('101', ['unrelated']).complete,
    'Only the linked photo satisfies the step',
  );
  answers['pressure']['result'] = 'fail';
  answers['pressure']['fault_requested'] = true;
  check(
    !progress('101', ['proof']).complete,
    'A finding does not repair a failed step',
  );
  check(
    !checklistAnswerValid(
      item['definition']! as Map<String, dynamic>,
      'pass',
      '30',
    ),
    'An out-of-range reading cannot be passed',
  );

  final input = <String, dynamic>{
    'answers': answers,
    'evidence_paths': ['proof'],
  };
  final command = ReportCommand(
    id: 'operation',
    revision: 3,
    action: 'submit',
    data: input,
  );
  answers['pressure']['note'] = 'edited later';
  final copy = command.data;
  (copy['answers'] as Map)['pressure']['note'] = 'transport mutation';
  final reopened = ReportCommand.fromJson(command.toJson());
  check(
    reopened.data['answers']['pressure']['note'] == '15',
    'Pending commands freeze nested input',
  );
  check(
    reopened.id == 'operation' && reopened.revision == 3,
    'Reopening keeps exact command identity',
  );

  check(
    !membershipAllows([], ['billing'], 'billing'),
    'An unaffiliated account cannot use delegated access',
  );
  check(
    !membershipAllows(['operator'], [], 'approve_work'),
    'An operator cannot approve work',
  );
  check(
    membershipAllows(['supervisor'], [], 'approve_work'),
    'A supervisor can approve assigned scope',
  );
  check(
    !membershipAllows(['supervisor'], [], 'billing'),
    'Supervision does not imply billing',
  );
  stdout.writeln('Portable work, command and membership contracts passed.');
}
