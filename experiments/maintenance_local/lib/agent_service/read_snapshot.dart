import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../evidence_store.dart';
import '../job_progress.dart';
import '../lab_store.dart';
import '../maintenance_domain.dart';
import '../model.dart';
import '../src/rust/api/documents.dart';
import 'errors.dart';

/// Captures ordinary store commands coherently, then decodes copied native
/// bytes. Evidence checks are bounded, referenced-only and never publish .part.
class AgentReadSnapshot {
  AgentReadSnapshot(
    this.catalog,
    this.progress,
    this.sourceFingerprint,
    Json evidence,
  ) : evidenceIdentities = Map.unmodifiable(evidence);
  final Json catalog;
  final WorkProgressSnapshot progress;
  final String sourceFingerprint;
  final Json evidenceIdentities;
}

String agentSourceFingerprint(LabStore store) => contentHash({
  'catalog': store.catalog,
  'documents': {
    for (final row in store.db.select(
      'SELECT id,bytes FROM documents ORDER BY id',
    ))
      row['id'] as String: digest(row['bytes']),
  },
  'submissions': store.submissions,
  'receipts': store.receipts,
});

Future<AgentReadSnapshot> readAgentSnapshot(LabStore store) async {
  final raw = await store.queue.run(() async {
    final catalog = store.catalog;
    if (catalog == null) throw const AgentFailure('not_found');
    validateCatalog(catalog);
    return _Raw(
      _copy(catalog),
      {
        for (final row in store.db.select('SELECT id,bytes FROM documents'))
          row['id'] as String: Uint8List.fromList(row['bytes'] as Uint8List),
      },
      store.submissions.map(_copy).toList(),
      store.receipts.map(_copy).toList(),
      agentSourceFingerprint(store),
    );
  });
  final views = <String, Json?>{}, references = <String>{};
  void referenced(Object? value) {
    if (value is String && hashPattern.hasMatch(value)) references.add(value);
  }

  for (final job in (raw.catalog['jobs'] as List).cast<Json>()) {
    final id = job['id'] as String, bytes = raw.documents[id];
    Json? view;
    if (bytes != null) {
      try {
        view = jsonDecode(await documentValues(bytes: bytes)) as Json;
        if (view['photo'] is List) {
          for (final value in view['photo'] as List) {
            referenced(value);
          }
        }
      } catch (_) {
        view = null;
      }
    }
    views[id] = view;
  }
  for (final submission in raw.submissions) {
    referenced((submission['values'] as Map?)?['photo']);
  }
  final evidence = agentEvidenceIdentities(store, references);
  final complete = {
    for (final hash in references) hash: evidence[hash] == hash,
  };
  final jobs = <String, JobProgress>{};
  final undecided = <SubmittedVersion>[], reviewed = <SubmittedVersion>[];
  final submissionsByJob = <String, List<Json>>{},
      receiptsByJob = <String, List<Json>>{};
  final submissionJobs = {
    for (final submission in raw.submissions)
      submission['id']: submission['jobId'],
  };
  for (final submission in raw.submissions) {
    submissionsByJob
        .putIfAbsent(submission['jobId'] as String, () => [])
        .add(submission);
  }
  for (final receipt in raw.receipts) {
    final jobId = submissionJobs[receipt['submissionId']];
    if (jobId is String) {
      receiptsByJob.putIfAbsent(jobId, () => []).add(receipt);
    }
  }
  for (final job in (raw.catalog['jobs'] as List).cast<Json>()) {
    final id = job['id'] as String;
    final context = <String, dynamic>{
      'companyId': raw.catalog['companyId'],
      'company': raw.catalog['company'],
      'coordinatorName': raw.catalog['coordinatorName'],
      'jobId': id,
      'equipmentId': job['equipmentId'],
      'equipment': job['equipmentSnapshot'],
      'job': job,
      'meterUnit': job['meterUnit'],
      'meterRequired': job['meterRequired'],
      'checklistSnapshot': job['checklistSnapshot'],
      'snapshotHash': job['snapshotHash'],
      'revision': job['revision'],
    };
    final progress = projectJobProgress(
      jobId: id,
      context: context,
      documentHash: raw.documents[id] == null
          ? null
          : digest(raw.documents[id]!),
      alternatives: views[id],
      submissions: submissionsByJob[id] ?? [],
      receipts: receiptsByJob[id] ?? [],
      evidenceComplete: complete,
    );
    jobs[id] = progress;
    for (final version in progress.history) {
      (version.receipt == null ? undecided : reviewed).add(version);
    }
  }
  return AgentReadSnapshot(
    raw.catalog,
    WorkProgressSnapshot(
      token: contentHash([raw.fingerprint, evidence]),
      jobs: jobs,
      undecided: undecided,
      reviewed: reviewed,
    ),
    raw.fingerprint,
    evidence,
  );
}

/// Only the captured references are consulted. Oversized, symlink, nonregular,
/// unreadable and unpublished files remain incomplete without following links
/// or allocating whole files. The final caller repeats this after authorization.
Json agentEvidenceIdentities(LabStore store, Iterable<String> references) => {
  for (final hash in references) hash: _identity(store.evidence.root, hash),
};

String _identity(Directory root, String hash) {
  try {
    final rootKind = FileSystemEntity.typeSync(root.path, followLinks: false);
    if (rootKind == FileSystemEntityType.notFound) return 'missing';
    if (rootKind != FileSystemEntityType.directory) return 'unavailable';
    final file = File('${root.path}/$hash');
    final kind = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (kind == FileSystemEntityType.notFound) return 'missing';
    if (kind != FileSystemEntityType.file) return 'nonregular';
    final length = file.lengthSync();
    if (length == 0) return 'empty';
    if (length > EvidenceStore.maxBytes) return 'oversized';
    final output = _HashSink();
    final digestSink = sha256.startChunkedConversion(output);
    final handle = file.openSync();
    var total = 0;
    try {
      while (true) {
        final chunk = handle.readSync(64 * 1024);
        if (chunk.isEmpty) break;
        total += chunk.length;
        if (total > EvidenceStore.maxBytes) return 'oversized';
        digestSink.add(chunk);
      }
    } finally {
      handle.closeSync();
      digestSink.close();
    }
    return total == 0 ? 'empty' : output.value.toString();
  } catch (_) {
    return 'unavailable';
  }
}

class _HashSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class _Raw {
  _Raw(
    this.catalog,
    this.documents,
    this.submissions,
    this.receipts,
    this.fingerprint,
  );
  final Json catalog;
  final Map<String, Uint8List> documents;
  final List<Json> submissions, receipts;
  final String fingerprint;
}

Json _copy(Json value) => jsonDecode(canonical(value)) as Json;
