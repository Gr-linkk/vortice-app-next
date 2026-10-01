import 'dart:convert';

import '../maintenance_domain.dart';
import '../model.dart';

class ProposalReviewFailure implements Exception {
  const ProposalReviewFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

/// Frozen suggestion read from the validated private proposal store. Human
/// review never changes this record or the agent's creation/retry response.
class NotesProposal {
  NotesProposal.fromRecord(Json record) : _encoded = canonical(record) {
    final frozen = this.record;
    final clean = Map<String, dynamic>.from(frozen)..remove('hash');
    final payload = frozen['payload'], result = frozen['result'];
    if (!_exactKeys(frozen, {
          'version',
          'grant_id',
          'actor_id',
          'payload',
          'context',
          'scope',
          'command',
          'result',
          'hash',
        }) ||
        frozen['version'] != 2 ||
        frozen['command'] != 'proposals.create' ||
        frozen['hash'] != contentHash(clean) ||
        frozen['context'] is! Json ||
        frozen['scope'] is! Json ||
        payload is! Json ||
        result is! Json ||
        !_exactKeys(payload, {
          'idempotency_key',
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
        }) ||
        !_exactKeys(result, {
          'proposal_id',
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
          'status',
          'requires_human_review',
          'applied',
          'created_at',
          'idempotency_key',
          'local_only',
          'backup_included',
          'human_review_available',
        }) ||
        !_exactKeys(frozen['scope'] as Json, {
          'workspace_id',
          'company_id',
          'device_id',
        }) ||
        !(frozen['scope'] as Json).values.every(
          (value) =>
              value is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value),
        ) ||
        payload['type'] != 'inspection.notes' ||
        result['status'] != 'pending_human_review' ||
        result['applied'] != false ||
        result['requires_human_review'] != true ||
        result['local_only'] != true ||
        result['backup_included'] != false ||
        result['human_review_available'] != false ||
        result['created_at'] is! String ||
        DateTime.tryParse(result['created_at'] as String)?.isUtc != true ||
        result['proposal_id'] is! String ||
        !reviewUuid.hasMatch(result['proposal_id'] as String) ||
        payload['idempotency_key'] is! String ||
        !reviewUuid.hasMatch(payload['idempotency_key'] as String) ||
        payload['expected_document_hash'] is! String ||
        !hashPattern.hasMatch(payload['expected_document_hash'] as String) ||
        payload['notes'] is! String ||
        (payload['notes'] as String).trim().isEmpty ||
        (payload['notes'] as String).length > 10000 ||
        frozen['grant_id'] is! String ||
        frozen['actor_id'] is! String ||
        frozen['scope']['company_id'] != frozen['context']['companyId'] ||
        payload['job_id'] != frozen['context']['jobId'] ||
        [
          'type',
          'job_id',
          'expected_document_hash',
          'notes',
          'idempotency_key',
        ].any((key) => result[key] != payload[key])) {
      throw const ProposalReviewFailure(
        'invalid_proposal',
        'This saved suggestion is invalid. Its files have been retained.',
      );
    }
    validateJobContext(frozen['context'] as Json);
  }
  final String _encoded;
  Json get record => jsonDecode(_encoded) as Json;
  Json get pendingResult => record['result'] as Json;
  Json get context => record['context'] as Json;
  Json get scope => record['scope'] as Json;
  String get id => pendingResult['proposal_id'] as String;
  String get jobId => pendingResult['job_id'] as String;
  String get notes => pendingResult['notes'] as String;
  String get expectedHash => pendingResult['expected_document_hash'] as String;
  String get hash => record['hash'] as String;
  String get grantId => record['grant_id'] as String;
  String get creationKey => pendingResult['idempotency_key'] as String;
}

final reviewUuid = RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
);
const notesReviewEvent = 'agent_notes_reviewed_v1';

/// Self-contained terminal history remains meaningful when pending sidecars
/// (intentionally outside backups) are absent after an office restore.
void validateNotesReviewHistory(
  List<Json> receipts, {
  required String companyId,
  String? reviewerDevice,
}) {
  final operations = <String>{},
      proposals = <String>{},
      creationKeys = <String>{};
  for (final receipt in receipts) {
    final clean = Map<String, dynamic>.from(receipt)..remove('hash');
    const keys = {
      'version',
      'operationId',
      'proposal',
      'reviewerDevice',
      'decision',
      'reason',
      'reviewedDocumentHash',
      'beforeDocumentHash',
      'afterDocumentHash',
      'reviewedAt',
      'requestHash',
      'hash',
    };
    if (receipt.length != keys.length ||
        !receipt.keys.every(keys.contains) ||
        receipt['version'] != 1 ||
        receipt['hash'] != contentHash(clean) ||
        receipt['proposal'] is! Json ||
        receipt['operationId'] is! String ||
        !reviewUuid.hasMatch(receipt['operationId'] as String) ||
        receipt['operationId'] !=
            (receipt['operationId'] as String).toLowerCase() ||
        receipt['reviewerDevice'] is! String ||
        !reviewUuid.hasMatch(receipt['reviewerDevice'] as String) ||
        receipt['reason'] is! String ||
        (receipt['reason'] as String).length > 2000 ||
        receipt['reviewedAt'] is! String ||
        DateTime.tryParse(receipt['reviewedAt'] as String)?.isUtc != true ||
        !['applied', 'rejected'].contains(receipt['decision']) ||
        [
          'reviewedDocumentHash',
          'beforeDocumentHash',
          'afterDocumentHash',
          'requestHash',
        ].any(
          (key) =>
              receipt[key] is! String ||
              !hashPattern.hasMatch(receipt[key] as String),
        )) {
      throw const ProposalReviewFailure(
        'invalid_history',
        'Saved suggestion review history is invalid. Its files have been retained.',
      );
    }
    final proposal = NotesProposal.fromRecord(receipt['proposal'] as Json);
    final applied = receipt['decision'] == 'applied';
    final reason = receipt['reason'] as String;
    if (proposal.scope['company_id'] != companyId ||
        proposal.scope['device_id'] != receipt['reviewerDevice'] ||
        (reviewerDevice != null &&
            receipt['reviewerDevice'] != reviewerDevice) ||
        reason != reason.trim() ||
        receipt['reviewedDocumentHash'] != receipt['beforeDocumentHash'] ||
        (applied &&
            (reason.isNotEmpty ||
                proposal.expectedHash != receipt['beforeDocumentHash'])) ||
        (!applied &&
            (reason.trim().isEmpty ||
                receipt['beforeDocumentHash'] !=
                    receipt['afterDocumentHash'])) ||
        receipt['requestHash'] !=
            notesReviewRequestHash(
              proposal,
              operationId: receipt['operationId'] as String,
              accept: applied,
              reason: reason,
              reviewedHash: receipt['reviewedDocumentHash'] as String,
            ) ||
        !operations.add(receipt['operationId'] as String) ||
        !proposals.add(proposal.id) ||
        !creationKeys.add(
          contentHash([proposal.grantId, proposal.creationKey]),
        )) {
      throw const ProposalReviewFailure(
        'invalid_history',
        'Saved suggestion review history is invalid. Its files have been retained.',
      );
    }
  }
}

String notesReviewRequestHash(
  NotesProposal proposal, {
  required String operationId,
  required bool accept,
  required String reason,
  required String reviewedHash,
}) => contentHash({
  'operationId': operationId,
  'proposalHash': proposal.hash,
  'accept': accept,
  'reason': reason,
  'reviewedHash': reviewedHash,
});

bool _exactKeys(Json value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);
