import 'model.dart';

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
}) => throw UnimplementedError('LF-002 projection implementation follows.');
