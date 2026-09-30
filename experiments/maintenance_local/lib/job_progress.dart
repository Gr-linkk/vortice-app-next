import 'model.dart';
import 'maintenance_domain.dart';
import 'package:maintenance_rules/checklist.dart';

enum DraftPhase { prepared, incomplete, ready, conflicted, unavailable }

enum PhotoState { none, complete, missingOrPartial, conflicted, unavailable }

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freeze(entry.value),
    });
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

Json _frozenJson(Json value) => _freeze(value) as Json;

/// One exact command and its known immutable decision, without actor ordering.
class SubmittedVersion {
  SubmittedVersion({
    required Json submission,
    Json? receipt,
    this.photoState = PhotoState.unavailable,
  }) : submission = _frozenJson(submission),
       receipt = receipt == null ? null : _frozenJson(receipt);

  final Json submission;
  final Json? receipt;
  final PhotoState photoState;
  String get id => submission['id'] as String;
  String get jobId => submission['jobId'] as String;
  String get device => submission['device'] as String;
  String get documentHash => submission['documentHash'] as String;
  int? get revision => submission['submissionRevision'] as int?;
  String? get localState => submission['_state'] as String?;
  String? get decision => receipt?['decision'] as String?;
}

class JobProgress {
  JobProgress({
    required this.jobId,
    required Json context,
    required this.documentHash,
    required this.draftPhase,
    required this.requiredAnswered,
    required this.requiredTotal,
    required List<String> conflictKeys,
    required this.problem,
    required this.photoState,
    required List<SubmittedVersion> currentVersions,
    required List<SubmittedVersion> history,
    required List<SubmittedVersion> queuedVersions,
  }) : context = _frozenJson(context),
       conflictKeys = List.unmodifiable(conflictKeys),
       currentVersions = List.unmodifiable(currentVersions),
       history = List.unmodifiable(history),
       queuedVersions = List.unmodifiable(queuedVersions);

  final String jobId;
  final Json context;
  final String? documentHash;
  final DraftPhase draftPhase;
  final int requiredAnswered, requiredTotal;
  final List<String> conflictKeys;
  final String? problem;
  final PhotoState photoState;
  final List<SubmittedVersion> currentVersions, history, queuedVersions;
  bool get ambiguousCurrentVersions => currentVersions.length > 1;
  List<SubmittedVersion> get approvedVersions => List.unmodifiable(
    history.where((version) => version.decision == 'approved'),
  );
  List<SubmittedVersion> get returnedVersions => List.unmodifiable(
    history.where((version) => version.decision == 'returned'),
  );
}

class WorkProgressSnapshot {
  WorkProgressSnapshot({
    required this.token,
    required Map<String, JobProgress> jobs,
    required List<SubmittedVersion> undecided,
    required List<SubmittedVersion> reviewed,
  }) : jobs = Map.unmodifiable(jobs),
       undecided = List.unmodifiable(undecided),
       reviewed = List.unmodifiable(reviewed);

  final String token;
  final Map<String, JobProgress> jobs;
  final List<SubmittedVersion> undecided, reviewed;
}

/// Projects captured data only. It never picks an active job or actor winner.
JobProgress projectJobProgress({
  required String jobId,
  required Json context,
  required String? documentHash,
  required Json? alternatives,
  required Iterable<Json> submissions,
  required Iterable<Json> receipts,
  required Map<String, bool> evidenceComplete,
}) {
  final decisions = <String, Json>{};
  for (final receipt in receipts) {
    final id = receipt['submissionId'] as String;
    final previous = decisions[id];
    if (previous != null && canonical(previous) != canonical(receipt)) {
      throw StateError('Conflicting immutable decisions in saved history.');
    }
    decisions[id] = receipt;
  }
  final history = <SubmittedVersion>[
    for (final submission in submissions)
      if (submission['jobId'] == jobId)
        SubmittedVersion(
          submission: submission,
          receipt: decisions[submission['id']],
          photoState: _photoFor(
            (submission['values'] as Map?)?['photo'],
            evidenceComplete,
          ),
        ),
  ];
  final current = history
      .where((version) => version.documentHash == documentHash)
      .toList();
  final queued = history
      .where((version) => version.localState == 'queued')
      .toList();
  var phase = DraftPhase.unavailable;
  var photo = PhotoState.unavailable;
  var requiredAnswered = 0, requiredTotal = 0;
  var conflictKeys = <String>[];
  String? problem = 'This saved inspection is unavailable. Retain its files.';
  try {
    final initial = initialJobFields(context);
    final items = ((context['checklistSnapshot'] as Map)['items'] as List)
        .cast<Json>();
    requiredTotal = items.where((item) => item['required'] != false).length;
    if (alternatives != null && documentHash != null) {
      validateJobDocument(alternatives, context);
      conflictKeys = conflicts(alternatives);
      for (final item in items.where((item) => item['required'] != false)) {
        final choices = alternatives['answer:${item['id']}'] as List;
        if (choices.length == 1 && _recordedAnswer(item, choices.single)) {
          requiredAnswered++;
        }
      }
      final photos = alternatives['photo'] as List;
      photo = photos.length > 1
          ? PhotoState.conflicted
          : _photoFor(photos.single, evidenceComplete);
      problem = incompleteJob(alternatives, context);
      if (conflictKeys.isNotEmpty) {
        phase = DraftPhase.conflicted;
      } else if (canonical(valuesOf(alternatives)) == canonical(initial)) {
        phase = DraftPhase.prepared;
      } else if (problem != null) {
        phase = DraftPhase.incomplete;
      } else if (photo != PhotoState.complete) {
        phase = DraftPhase.incomplete;
        problem = 'Save the complete photo first.';
      } else {
        phase = DraftPhase.ready;
      }
    }
  } on StateError {
    // A projection cannot repair or choose a winner for malformed saved work.
    phase = DraftPhase.unavailable;
    photo = PhotoState.unavailable;
    requiredAnswered = 0;
    conflictKeys = [];
    problem = 'This saved inspection is unavailable. Retain its files.';
  } on TypeError {
    phase = DraftPhase.unavailable;
    photo = PhotoState.unavailable;
    requiredAnswered = 0;
    conflictKeys = [];
    problem = 'This saved inspection is unavailable. Retain its files.';
  }
  return JobProgress(
    jobId: jobId,
    context: context,
    documentHash: documentHash,
    draftPhase: phase,
    requiredAnswered: requiredAnswered,
    requiredTotal: requiredTotal,
    conflictKeys: conflictKeys,
    problem: problem,
    photoState: photo,
    currentVersions: current,
    history: history,
    queuedVersions: queued,
  );
}

PhotoState _photoFor(Object? hash, Map<String, bool> evidence) => hash == null
    ? PhotoState.none
    : hash is String && evidence[hash] == true
    ? PhotoState.complete
    : PhotoState.missingOrPartial;

bool _recordedAnswer(Json item, Object? raw) {
  if (raw is! Map) return false;
  final result = raw['result'] == 'attention' ? 'action' : raw['result'];
  final value = raw['value'];
  if (value is! String ||
      !checklistAnswerValid(
        {...item, 'allow_na': item['allow_na'] == true},
        result as String?,
        value,
      )) {
    return false;
  }
  if (item['input_type'] == 'number' && result != 'na') {
    final number = double.tryParse(value.trim().replaceAll(',', '.'));
    return number != null && number.isFinite && number.abs() <= 1e12;
  }
  return true;
}
