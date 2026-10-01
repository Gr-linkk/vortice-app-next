import 'package:flutter/material.dart';
import '../job_progress.dart';
import '../lab_store.dart';
import '../work_progress_reader.dart';
import 'common.dart';

typedef ProgressReader = Future<WorkProgressSnapshot> Function(LabStore store);
typedef ProgressTokenReader = Future<String> Function(LabStore store);

/// Owns one bulk read for a view. No widget build decodes job documents.
class WorkProgressController extends ChangeNotifier {
  WorkProgressController(
    this.store, {
    this.reader = readWorkProgress,
    this.tokenReader = workProgressToken,
  });

  final LabStore store;
  final ProgressReader reader;
  final ProgressTokenReader tokenReader;
  WorkProgressSnapshot? snapshot;
  WorkProgressSnapshot? _cached;
  String? error;
  bool loading = false;
  int _generation = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    snapshot = null;
    error = null;
    loading = true;
    notifyListeners();
    try {
      final token = await tokenReader(store);
      if (_disposed || generation != _generation) return;
      final next = _cached?.token == token ? _cached! : await reader(store);
      final currentToken = await tokenReader(store);
      if (_disposed || generation != _generation) return;
      if (next.token != currentToken) {
        // A write or evidence change overtook this captured read.
        await refresh();
        return;
      }
      snapshot = _cached = next;
      loading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      loading = false;
      error =
          'Current work status could not be read. Your saved work and submitted versions have been retained.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

String draftPhaseLabel(DraftPhase phase) => switch (phase) {
  DraftPhase.prepared => 'Prepared · Ready to inspect',
  DraftPhase.incomplete => 'Incomplete · Continue inspection',
  DraftPhase.ready => 'Ready · Required information recorded',
  DraftPhase.conflicted => 'Conflicting work · Resolve before submitting',
  DraftPhase.unavailable => 'Unavailable · Saved history retained',
};

String versionStatus(SubmittedVersion version) => switch (version.decision) {
  'approved' => 'Approved inspection',
  'returned' => 'Returned — ${version.receipt!['reason']}',
  _ => version.localState == 'queued' ? 'Waiting to send' : 'Awaiting review',
};

String deviceVersionLabel(SubmittedVersion version) =>
    'Device version ${version.revision ?? 1}';

String submissionSavedMessage(
  SubmittedVersion version, {
  required bool existing,
  required bool office,
  required bool sendingStatusShown,
}) {
  if (existing) {
    final label = deviceVersionLabel(version).toLowerCase();
    return switch (version.decision) {
      'returned' =>
        'Existing $label was returned: ${version.receipt!['reason']}. Save corrections before submitting a new version.',
      'approved' =>
        'Existing $label is approved. Its saved decision is unchanged; no new version was created.',
      _ =>
        'Existing $label is ${version.localState == 'queued' ? 'waiting to send' : 'awaiting review'}. No new version was created.',
    };
  }
  return office
      ? 'Submitted for computer review.'
      : sendingStatusShown
      ? 'Version saved for review. Its sending status is shown above.'
      : 'Saved on this phone—waiting to send.';
}

String photoStateLabel(PhotoState state) => switch (state) {
  PhotoState.none => 'No inspection photo saved yet.',
  PhotoState.complete => 'Inspection photo complete on this device.',
  PhotoState.missingOrPartial =>
    'Inspection photo is missing or incomplete on this device.',
  PhotoState.conflicted => 'Resolve the conflicting inspection photo.',
  PhotoState.unavailable => 'Inspection photo status unavailable.',
};

class DraftProgressView extends StatelessWidget {
  const DraftProgressView({
    super.key,
    required this.progress,
    required this.localDevice,
  });
  final JobProgress progress;
  final String localDevice;

  @override
  Widget build(BuildContext context) {
    final earlierCount = progress.history
        .where(
          (version) => !progress.currentVersions.any(
            (current) => current.id == version.id,
          ),
        )
        .length;
    return Column(
      key: ValueKey('draft-progress:${progress.jobId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Current draft: ${draftPhaseLabel(progress.draftPhase)}'),
        Text(
          'Required steps: ${progress.requiredAnswered} of ${progress.requiredTotal} recorded',
        ),
        Text(photoStateLabel(progress.photoState)),
        if (progress.problem != null &&
            progress.draftPhase != DraftPhase.prepared)
          Text(progress.problem!),
        if (progress.currentVersions.isEmpty && progress.documentHash != null)
          Text(
            progress.history.isEmpty
                ? 'No submitted versions yet.'
                : 'This draft has not been submitted. Earlier versions stay in history.',
          ),
        if (progress.ambiguousCurrentVersions)
          const Text(
            'More than one device submitted this exact draft. Each record and decision is shown separately.',
          ),
        for (final version in progress.currentVersions)
          Text(
            'Current submitted record · ${deviceVersionLabel(version)}: ${versionStatus(version)}',
          ),
        if (progress.currentVersions.any(
          (version) => version.device == localDevice,
        ))
          const Text(
            'Submitting this unchanged draft reuses its existing record.',
          ),
        if (earlierCount > 0)
          Text(
            '$earlierCount earlier submitted ${earlierCount == 1 ? 'version' : 'versions'} retained.',
          ),
        if (progress.queuedVersions.any(
          (version) => !progress.currentVersions.any(
            (current) => current.id == version.id,
          ),
        ))
          const Text('An earlier submitted version is also waiting to send.'),
      ],
    );
  }
}

class ReturnedWorkView extends StatelessWidget {
  const ReturnedWorkView({
    super.key,
    required this.progress,
    this.correctionSubmissionId,
  });
  final JobProgress progress;
  final String? correctionSubmissionId;

  @override
  Widget build(BuildContext context) {
    final returns = {
      for (final version in progress.returnedVersions) version.id: version,
    }.values.toList();
    final pinned = returns
        .where((version) => version.id == correctionSubmissionId)
        .firstOrNull;
    final current = progress.currentVersions.where(
      (version) => version.decision == 'returned',
    );
    final shown = pinned == null ? current.toList() : [pinned];
    final earlier = returns
        .where((version) => !shown.any((item) => item.id == version.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final version in shown) ...[
          notice('Returned: ${version.receipt!['reason']}'),
          Text(
            'Return reason for ${deviceVersionLabel(version).toLowerCase()}. Save corrections and submit a new version; this returned record stays unchanged.',
          ),
        ],
        if (earlier.isNotEmpty)
          ExpansionTile(
            key: ValueKey('earlier-returns:${progress.jobId}'),
            title: Text('Earlier return reasons (${earlier.length})'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'These reasons belong to earlier submitted records. They do not change the current draft or its decisions.',
              ),
              for (final version in earlier)
                Text(
                  '${deviceVersionLabel(version)} · ${version.receipt!['reason']}',
                ),
            ],
          ),
      ],
    );
  }
}
