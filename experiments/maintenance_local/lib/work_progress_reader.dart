import 'dart:convert';
import 'dart:typed_data';
import 'lab_store.dart';
import 'job_progress.dart';
import 'maintenance_domain.dart';
import 'model.dart';
import 'src/rust/api/documents.dart';

/// A coherent, read-only company view. Compare its token before rendering a
/// late result; selection alone is excluded from projection freshness.
Future<WorkProgressSnapshot> readWorkProgress(LabStore store) async {
  final captured = await _capture(store);
  final decoded = await _decode(store, captured);
  final submissionsByJob = <String, List<Json>>{};
  final submissionJobs = <String, String>{};
  for (final submission in captured.submissions) {
    submissionJobs[submission['id'] as String] = submission['jobId'] as String;
    submissionsByJob
        .putIfAbsent(submission['jobId'] as String, () => [])
        .add(submission);
  }
  final receiptsByJob = <String, List<Json>>{};
  for (final receipt in captured.receipts) {
    final jobId = submissionJobs[receipt['submissionId']];
    if (jobId != null) {
      receiptsByJob.putIfAbsent(jobId, () => []).add(receipt);
    }
  }
  final jobs = <String, JobProgress>{};
  final undecided = <SubmittedVersion>[], reviewed = <SubmittedVersion>[];
  for (final entry in captured.contexts.entries) {
    final progress = projectJobProgress(
      jobId: entry.key,
      context: entry.value,
      documentHash: captured.documents[entry.key] == null
          ? null
          : digest(captured.documents[entry.key]!),
      alternatives: decoded.alternatives[entry.key],
      submissions: submissionsByJob[entry.key] ?? [],
      receipts: receiptsByJob[entry.key] ?? [],
      evidenceComplete: decoded.evidence,
    );
    jobs[entry.key] = progress;
    for (final version in progress.history) {
      (version.receipt == null ? undecided : reviewed).add(version);
    }
  }
  return WorkProgressSnapshot(
    token: _token(captured, decoded.evidence),
    jobs: jobs,
    undecided: undecided,
    reviewed: reviewed,
  );
}

/// Fingerprint of all data that can change this projection, including evidence.
Future<String> workProgressToken(LabStore store) async {
  final captured = await _capture(store);
  final decoded = await _decode(store, captured);
  return _token(captured, decoded.evidence);
}

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;

class _CapturedWork {
  _CapturedWork(
    this.catalog,
    this.contexts,
    this.documents,
    this.submissions,
    this.receipts,
  );
  final Json? catalog;
  final Map<String, Json> contexts;
  final Map<String, Uint8List?> documents;
  final List<Json> submissions, receipts;
}

Future<_CapturedWork> _capture(LabStore store) => store.queue.run(() async {
  final catalog = store.catalog;
  final contexts = <String, Json>{};
  final documents = <String, Uint8List?>{};
  if (catalog != null) {
    validateCatalog(catalog);
    // One table read and one catalog validation avoid rescanning the full
    // catalog through each active-document convenience getter.
    final rows = {
      for (final row in store.db.select('SELECT id,bytes FROM documents'))
        row['id'] as String: row['bytes'] as Uint8List,
    };
    for (final job in (catalog['jobs'] as List).cast<Json>()) {
      final id = job['id'] as String;
      contexts[id] = _copy({
        'companyId': catalog['companyId'],
        'company': catalog['company'],
        'coordinatorName': catalog['coordinatorName'],
        'jobId': id,
        'equipmentId': job['equipmentId'],
        'equipment': job['equipmentSnapshot'],
        'job': job,
        'meterUnit': job['meterUnit'],
        'meterRequired': job['meterRequired'],
        'checklistSnapshot': job['checklistSnapshot'],
        'snapshotHash': job['snapshotHash'],
        'revision': job['revision'],
      });
      final bytes = rows[id];
      documents[id] = bytes == null ? null : Uint8List.fromList(bytes);
    }
  }
  return _CapturedWork(
    catalog == null ? null : _copy(catalog),
    contexts,
    documents,
    store.submissions.map(_copy).toList(),
    store.receipts.map(_copy).toList(),
  );
});

class _DecodedWork {
  _DecodedWork(this.alternatives, this.evidence);
  final Map<String, Json?> alternatives;
  final Map<String, bool> evidence;
}

Future<_DecodedWork> _decode(LabStore store, _CapturedWork captured) async {
  final alternatives = <String, Json?>{};
  final hashes = <String>{};
  void referenced(Object? hash) {
    if (hash is String && hashPattern.hasMatch(hash)) hashes.add(hash);
  }

  for (final entry in captured.documents.entries) {
    Json? view;
    if (entry.value != null) {
      try {
        view = jsonDecode(await documentValues(bytes: entry.value!)) as Json;
        final photos = view['photo'];
        if (photos is List) {
          for (final photo in photos) {
            referenced(photo);
          }
        }
      } catch (_) {
        // Decode failure makes this job unavailable without discarding history.
      }
    }
    alternatives[entry.key] = view;
  }
  for (final submission in captured.submissions) {
    referenced((submission['values'] as Map?)?['photo']);
  }
  final evidence = <String, bool>{};
  // Integrity is checked once per unique referenced hash. complete() does not
  // rename partials or write files; no evidence status/recovery API is invoked.
  for (final hash in hashes) {
    try {
      evidence[hash] = await store.evidence.complete(hash);
    } catch (_) {
      evidence[hash] = false;
    }
  }
  return _DecodedWork(alternatives, evidence);
}

String _token(_CapturedWork captured, Map<String, bool> evidence) =>
    contentHash({
      'catalog': captured.catalog,
      'documents': {
        for (final entry in captured.documents.entries)
          entry.key: entry.value == null ? null : digest(entry.value!),
      },
      'submissions': captured.submissions,
      'receipts': captured.receipts,
      'evidenceComplete': evidence,
    });
