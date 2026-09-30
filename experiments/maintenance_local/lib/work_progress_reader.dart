import 'lab_store.dart';
import 'job_progress.dart';

/// A coherent, read-only company view. Compare its token before rendering a
/// late result; selection alone is excluded from projection freshness.
Future<WorkProgressSnapshot> readWorkProgress(LabStore store) =>
    throw UnimplementedError('LF-002 reader implementation follows.');

/// Fingerprint of all data that can change this projection, including evidence.
Future<String> workProgressToken(LabStore store) =>
    throw UnimplementedError('LF-002 reader implementation follows.');
