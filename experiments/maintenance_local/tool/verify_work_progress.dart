import '../lib/job_progress.dart';
import '../lib/maintenance_domain.dart';
import '../lib/model.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Compile and exercise the projection with Dart alone. Native storage and
/// Flutter presentation must remain outside this domain boundary.
void main() {
  final equipment = makeEquipment(id: 'machine', name: 'Synthetic machine');
  final template = makeTemplate(
    id: 'procedure',
    title: 'Synthetic inspection',
    items: [
      {'id': 'guard', 'label': 'Check guard', 'input_type': 'check'},
    ],
    provenance: {'kind': 'company-authored'},
  );
  final job = makeJob(
    id: 'work',
    title: 'Synthetic work',
    equipment: equipment,
    template: template,
  );
  final catalog = makeCatalog(
    id: 'company',
    name: 'Synthetic company',
    coordinatorName: 'Coordinator',
  );
  (catalog['equipment'] as List).add(equipment);
  (catalog['templates'] as List).add(template);
  (catalog['jobs'] as List).add(job);
  final context = jobContext(catalog, 'work');
  final initial = initialJobFields(context);
  Json alternatives(Json values) => {
    for (final entry in values.entries) entry.key: [entry.value],
  };
  final prepared = projectJobProgress(
    jobId: 'work',
    context: context,
    documentHash: contentHash(initial),
    alternatives: alternatives(initial),
    submissions: [],
    receipts: [],
    evidenceComplete: {},
  );
  require(
    prepared.draftPhase == DraftPhase.prepared,
    'Pristine work is prepared.',
  );
  require(
    prepared.requiredAnswered == 0 && prepared.requiredTotal == 1,
    'Required steps retain their definition.',
  );
  final photo = digest([1, 2, 3]);
  final complete = {
    ...initial,
    'answer:guard': {'result': 'action', 'value': ''},
    'meter': 0,
    'notes': 'Guard needs attention.',
    'photo': photo,
  };
  final priorHash = contentHash(complete);
  final ready = projectJobProgress(
    jobId: 'work',
    context: context,
    documentHash: priorHash,
    alternatives: alternatives(complete),
    submissions: [],
    receipts: [],
    evidenceComplete: {photo: true},
  );
  require(
    ready.draftPhase == DraftPhase.ready && ready.requiredAnswered == 1,
    'An honest finding with complete evidence is ready for review.',
  );
  final edited = projectJobProgress(
    jobId: 'work',
    context: context,
    documentHash: digest([4, 5, 6]),
    alternatives: alternatives(complete),
    submissions: [
      {
        'id': 'command',
        'jobId': 'work',
        'device': 'mechanic',
        'documentHash': priorHash,
        'submissionRevision': 1,
        'values': complete,
        '_state': 'received',
      },
    ],
    receipts: [
      {'submissionId': 'command', 'decision': 'approved'},
    ],
    evidenceComplete: {photo: true},
  );
  require(
    edited.currentVersions.isEmpty && edited.approvedVersions.length == 1,
    'Different document bytes retain history without inheriting approval.',
  );
  var immutable = false;
  try {
    edited.context['jobId'] = 'changed';
  } on UnsupportedError {
    immutable = true;
  }
  require(immutable, 'Captured projection context is immutable.');
  print('Pure Dart work progress and exact history boundary passed.');
}
