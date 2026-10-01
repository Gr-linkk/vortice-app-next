import '../lab_store.dart';
import '../model.dart';
import 'proposal_review_rules.dart';
import 'proposal_store.dart';

export 'proposal_review_rules.dart';

class NotesProposalView {
  const NotesProposalView({
    required this.proposal,
    required this.currentHash,
    required this.currentNotes,
    required this.receipt,
  });
  final NotesProposal proposal;
  final String currentHash;
  final List<String> currentNotes;
  final Json? receipt;
  bool get stale => currentHash != proposal.expectedHash;
}

/// Trusted office UI adapter, separate from the permission-checked external
/// agent service. Its scope is supplied by the desktop lifecycle, never by an
/// agent's request or a saved sidecar.
class AgentProposalReviewer {
  AgentProposalReviewer({
    required this.store,
    required this.workspaceId,
    required this.serviceDeviceId,
    AgentProposalStore? proposals,
  }) : proposals = proposals ?? AgentProposalStore(store.root);
  final LabStore store;
  final String workspaceId, serviceDeviceId;
  final AgentProposalStore proposals;

  void _office() {
    store.requireOffice();
    if (!store.realWorkspace || serviceDeviceId != store.device) {
      throw const ProposalReviewFailure(
        'scope_mismatch',
        'Open the company on its office computer to review suggested notes.',
      );
    }
  }

  bool _scope(NotesProposal proposal) =>
      proposal.scope['workspace_id'] == workspaceId &&
      proposal.scope['company_id'] == store.catalog!['companyId'] &&
      proposal.scope['device_id'] == serviceDeviceId;

  Future<List<NotesProposal>> pending() async {
    _office();
    final records = await proposals.records();
    return store.queue.run(() async {
      _office();
      final history = store.agentNotesReviews;
      return records
          .map(NotesProposal.fromRecord)
          .where(
            (p) =>
                _scope(p) &&
                !history.any((r) {
                  final original = NotesProposal.fromRecord(
                    r['proposal'] as Json,
                  );
                  return original.id == p.id ||
                      (original.grantId == p.grantId &&
                          original.creationKey == p.creationKey);
                }),
          )
          .toList();
    });
  }

  Future<NotesProposalView> show(String id) async {
    _office();
    final records = await proposals.records();
    final proposal = records
        .map(NotesProposal.fromRecord)
        .where((p) => p.id == id && _scope(p))
        .firstOrNull;
    if (proposal == null) {
      throw const ProposalReviewFailure(
        'not_found',
        'Suggested notes were not found in this workspace.',
      );
    }
    return store.queue.run(() async {
      _office();
      if (canonical(store.jobContextFor(proposal.jobId)) !=
          canonical(proposal.context)) {
        throw const ProposalReviewFailure(
          'stale_context',
          'The work order context changed. These notes cannot be applied.',
        );
      }
      final bytes = store.documentFor(proposal.jobId);
      if (bytes == null) {
        throw const ProposalReviewFailure(
          'not_found',
          'This inspection is unavailable.',
        );
      }
      final fields = await store.fields(jobId: proposal.jobId);
      final notes = (fields['notes'] as List).cast<String>();
      final receipt = store.agentNotesReviews.where((r) {
        final original = NotesProposal.fromRecord(r['proposal'] as Json);
        return original.id == proposal.id ||
            (original.grantId == proposal.grantId &&
                original.creationKey == proposal.creationKey);
      }).firstOrNull;
      return NotesProposalView(
        proposal: proposal,
        currentHash: digest(bytes),
        currentNotes: List.unmodifiable(notes),
        receipt: receipt,
      );
    });
  }

  Future<Json> decide(
    NotesProposalView view, {
    required String operationId,
    required bool accept,
    String reason = '',
  }) {
    _office();
    return store.reviewAgentNotes(
      view.proposal,
      operationId: operationId,
      accept: accept,
      reason: reason,
      reviewedDocumentHash: view.currentHash,
      workspaceId: workspaceId,
      serviceDeviceId: serviceDeviceId,
    );
  }

  Future<List<Json>> history() => store.queue.run(() async {
    _office();
    return store.agentNotesReviews
        .where((r) => _scope(NotesProposal.fromRecord(r['proposal'] as Json)))
        .toList();
  });
}
