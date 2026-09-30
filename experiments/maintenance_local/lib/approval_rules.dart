import 'dart:convert';
import 'model.dart';
import 'maintenance_domain.dart';
import 'src/rust/api/documents.dart';

/// Inspection policy is independent of transport. Office decisions bind one version.
class ApprovalRules {
  static bool _id(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 100;
  static bool _date(Object? value) =>
      value is String && DateTime.tryParse(value) != null;

  static Future<void> validateSubmission(
    Json p,
    Json? workspace, {
    bool allowLocalState = false,
  }) async {
    if (!allowLocalState && p.containsKey('_state')) {
      throw StateError(
        'Local send status cannot be submitted. Retry the original submission without local status metadata; saved work has been retained.',
      );
    }
    final real = workspace?.containsKey('checklistSnapshot') == true;
    final allowed = {
      'id',
      'companyId',
      'jobId',
      'device',
      'createdAt',
      'document',
      'documentHash',
      'values',
      if (allowLocalState) '_state',
      if (real) ...{
        'schemaVersion',
        'equipmentId',
        'snapshotHash',
        'revision',
        'context',
        'submissionRevision',
        'predecessorId',
      },
    };
    final required = {...allowed}..remove('_state');
    if (p.keys.toSet().difference(allowed).isNotEmpty ||
        required.difference(p.keys.toSet()).isNotEmpty ||
        !_date(p['createdAt']) ||
        p['document'] is! String ||
        p['documentHash'] is! String ||
        !hashPattern.hasMatch(p['documentHash'] as String) ||
        p['values'] is! Json) {
      throw StateError(
        'Invalid submitted record. Saved work has been retained.',
      );
    }
    if (!_id(p['id']) ||
        !_id(p['device']) ||
        p['companyId'] != workspace?['companyId'] ||
        p['jobId'] != workspace?['jobId']) {
      throw StateError('Submission belongs to a different job or company.');
    }
    if (real &&
        (p['schemaVersion'] != 1 ||
            p['equipmentId'] != workspace!['equipmentId'] ||
            p['snapshotHash'] != workspace['snapshotHash'] ||
            p['revision'] != workspace['revision'] ||
            p['context'] is! Json ||
            canonical(p['context']) != canonical(workspace) ||
            p['submissionRevision'] is! int ||
            (p['submissionRevision'] as int) < 1 ||
            (p['predecessorId'] != null && !_id(p['predecessorId'])) ||
            ((p['submissionRevision'] == 1) != (p['predecessorId'] == null)))) {
      throw StateError(
        'Submitted work does not match its frozen work-order context.',
      );
    }
    final bytes = base64Decode(p['document'] as String);
    if (bytes.isEmpty ||
        bytes.length > 16 * 1024 * 1024 ||
        digest(bytes) != p['documentHash']) {
      throw StateError('Submitted version failed its integrity check.');
    }
    final view = jsonDecode(await documentValues(bytes: bytes)) as Json;
    final problem = real ? incompleteJob(view, workspace!) : incomplete(view);
    if (problem != null) throw StateError(problem);
    if (canonical(valuesOf(view)) != canonical(p['values'])) {
      throw StateError('Submitted answers do not match their version.');
    }
  }

  static void validateReceipt(Json r, Json submission, {Json? workspace}) {
    final real = workspace?.containsKey('checklistSnapshot') == true;
    final allowed = {
      'id',
      'submissionId',
      'submissionHash',
      'decision',
      'reason',
      'reviewedAt',
      'reviewedBy',
      'values',
      if (real) 'reviewerDevice',
    };
    if (r.keys.toSet().difference(allowed).isNotEmpty ||
        allowed.difference(r.keys.toSet()).isNotEmpty ||
        !_id(r['id']) ||
        r['submissionId'] != submission['id'] ||
        r['submissionHash'] !=
            contentHash(
              Map<String, dynamic>.from(submission)..remove('_state'),
            ) ||
        !{'approved', 'returned'}.contains(r['decision']) ||
        r['reason'] is! String ||
        (r['reason'] as String).length > 10000 ||
        (r['decision'] == 'returned' &&
            (r['reason'] as String).trim().isEmpty) ||
        !_date(r['reviewedAt']) ||
        r['reviewedBy'] !=
            (real ? workspace!['coordinatorName'] : 'Office owner') ||
        (real && !_id(r['reviewerDevice'])) ||
        canonical(r['values']) != canonical(submission['values'])) {
      throw StateError(
        'Invalid immutable office decision. Saved history has been retained.',
      );
    }
  }

  static void validateSubmissionHistory(Iterable<Json> history) {
    final byId = <String, Json>{for (final p in history) p['id'] as String: p};
    final revisions = <String, Set<int>>{};
    final documentVersions = <String>{};
    for (final p in byId.values) {
      if (p['schemaVersion'] != 1) continue;
      if (!documentVersions.add(
        canonical([p['device'], p['jobId'], p['documentHash']]),
      )) {
        throw StateError(
          'Submitted history assigns more than one record to the same device, work order and document version. Retain the saved history and reconcile the original submissions.',
        );
      }
      final revision = p['submissionRevision'] as int;
      final predecessor = byId[p['predecessorId']];
      final key = canonical([p['device'], p['jobId']]);
      if (!revisions.putIfAbsent(key, () => <int>{}).add(revision) ||
          (revision == 1
              ? predecessor != null
              : predecessor == null ||
                    predecessor['device'] != p['device'] ||
                    predecessor['jobId'] != p['jobId'] ||
                    predecessor['submissionRevision'] != revision - 1)) {
        throw StateError('Invalid submitted revision history.');
      }
    }
  }

  static Future<String?> problem({
    required Json submission,
    required Json? workspace,
    required Json current,
    String? currentDocumentHash,
    required Future<bool> Function(String) completeEvidence,
  }) async {
    // Getter records include a local SQL status for display. That metadata is
    // allowed here only; stored, transferred and restored commands stay clean.
    await validateSubmission(submission, workspace, allowLocalState: true);
    if (!await completeEvidence(
      (submission['values'] as Json)['photo'] as String,
    )) {
      return 'Waiting for the complete photo.';
    }
    if (conflicts(current).isNotEmpty) {
      return 'Resolve conflicting work before reviewing.';
    }
    if ((workspace?.containsKey('checklistSnapshot') == true &&
            currentDocumentHash != submission['documentHash']) ||
        canonical(valuesOf(current)) != canonical(submission['values'])) {
      return 'Work has changed. Return this version and request a new submission.';
    }
    return null;
  }
}
