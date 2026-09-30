import 'dart:convert';
import 'model.dart';
import 'src/rust/api/documents.dart';

/// Approval policy is independent of transport, database writes and UI.
/// The owner command persists a receipt only after these checks succeed.
class ApprovalRules {
  static Future<void> validateSubmission(Json p, Json? workspace) async {
    const allowed = {
      'id',
      'companyId',
      'jobId',
      'device',
      'createdAt',
      'document',
      'documentHash',
      'values',
      '_state',
    };
    if (p.keys.toSet().difference(allowed).isNotEmpty ||
        p['createdAt'] is! String ||
        DateTime.tryParse(p['createdAt'] as String) == null ||
        p['document'] is! String ||
        p['documentHash'] is! String ||
        !hashPattern.hasMatch(p['documentHash'] as String) ||
        p['values'] is! Map) {
      throw StateError(
        'Invalid submitted record. Saved work has been retained.',
      );
    }
    if (p['id'] is! String ||
        (p['id'] as String).isEmpty ||
        (p['id'] as String).length > 100 ||
        p['device'] is! String ||
        p['companyId'] != workspace?['companyId'] ||
        p['jobId'] != workspace?['jobId']) {
      throw StateError('Submission belongs to a different job or company.');
    }
    final bytes = base64Decode(p['document'] as String);
    if (digest(bytes) != p['documentHash']) {
      throw StateError('Submitted version failed its integrity check.');
    }
    final view = jsonDecode(await documentValues(bytes: bytes)) as Json;
    final problem = incomplete(view);
    if (problem != null) throw StateError(problem);
    if (canonical(valuesOf(view)) != canonical(p['values'])) {
      throw StateError('Submitted answers do not match their version.');
    }
  }

  static Future<String?> problem({
    required Json submission,
    required Json? workspace,
    required Json current,
    required Future<bool> Function(String) completeEvidence,
  }) async {
    await validateSubmission(submission, workspace);
    if (!await completeEvidence(
      (submission['values'] as Json)['photo'] as String,
    )) {
      return 'Waiting for the complete photo.';
    }
    if (conflicts(current).isNotEmpty) {
      return 'Resolve conflicting work before reviewing.';
    }
    if (canonical(valuesOf(current)) != canonical(submission['values'])) {
      return 'Work has changed. Return this version and request a new submission.';
    }
    return null;
  }
}
