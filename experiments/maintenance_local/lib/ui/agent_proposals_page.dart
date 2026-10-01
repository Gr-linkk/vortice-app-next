import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../agent_service/proposal_review.dart';
import '../model.dart';
import 'common.dart';
import 'inspection_content.dart';

/// Human office review. External agents only submit the frozen suggestions;
/// this screen calls the existing office command through its trusted adapter.
class AgentProposalsPage extends StatefulWidget {
  const AgentProposalsPage({super.key, required this.reviewer});
  final AgentProposalReviewer reviewer;

  @override
  State<AgentProposalsPage> createState() => _AgentProposalsPageState();
}

class _AgentProposalsPageState extends State<AgentProposalsPage> {
  List<NotesProposal>? pending;
  List<Json> history = [];
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // History is independent of the pending files, including after restore.
      final decisions = await widget.reviewer.history();
      if (mounted) setState(() => history = decisions.reversed.toList());
      final suggestions = await widget.reviewer.pending();
      if (mounted) setState(() => pending = suggestions);
    } catch (failure) {
      if (mounted) setState(() => error = _failureMessage(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(NotesProposal proposal) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ProposalPage(reviewer: widget.reviewer, proposalId: proposal.id),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent suggestions')),
    body: page([
      const Text(
        'Review suggested inspection notes before applying them to a draft. '
        'Submitting and approving an inspection are separate actions.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh suggestions'),
        ),
      ),
      if (loading) const LinearProgressIndicator(),
      if (error != null) notice(error!, error: true),
      _heading(context, 'Awaiting your review'),
      if (pending != null && pending!.isEmpty)
        const Text('No suggested notes are waiting for review.'),
      for (final proposal in pending ?? <NotesProposal>[])
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _contextText(context, proposal.context),
                const SizedBox(height: 8),
                const Text('Suggested replacement notes'),
                Text(
                  proposal.notes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: loading ? null : () => open(proposal),
                  child: const Text('Review suggested notes'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 20),
      _heading(context, 'Review history'),
      if (history.isEmpty) const Text('No suggestions have been reviewed yet.'),
      for (final receipt in history)
        _HistoryCard(
          receipt: receipt,
          onOpen: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => _HistoryPage(receipt: receipt)),
          ),
        ),
    ]),
  );
}

class _ProposalPage extends StatefulWidget {
  const _ProposalPage({required this.reviewer, required this.proposalId});
  final AgentProposalReviewer reviewer;
  final String proposalId;

  @override
  State<_ProposalPage> createState() => _ProposalPageState();
}

class _ReviewIntent {
  _ReviewIntent(this.view, this.accept, this.reason) : id = const Uuid().v4();
  final NotesProposalView view;
  final bool accept;
  final String reason, id;
}

class _ProposalPageState extends State<_ProposalPage> {
  NotesProposalView? view;
  Json? receipt;
  _ReviewIntent? intent;
  String? message;
  bool busy = false, uncertain = false, changed = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (busy || uncertain) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final current = await widget.reviewer.show(widget.proposalId);
      if (mounted) {
        setState(() {
          view = current;
          receipt = current.receipt;
          changed = false;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => message = _failureMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm(bool accept) async {
    final current = view;
    if (busy || uncertain || receipt != null || current == null) return;
    String reason = '';
    if (accept) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Apply suggested notes?'),
          content: const Text(
            'This replaces the current draft notes with the suggested text. '
            'The inspection still needs its normal submission and review.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply to draft notes'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else {
      final text = await askText(
        context,
        'Reject suggested notes',
        'Reason for rejection',
        multiline: true,
        instructions:
            'Your reason is saved in review history. Draft notes stay unchanged.',
      );
      if (text == null) return;
      reason = text.trim();
      if (reason.isEmpty || reason.length > 2000) {
        if (mounted) {
          setState(() => message = 'Enter a reason of 1 to 2,000 characters.');
        }
        return;
      }
    }
    if (!mounted) return;
    intent = _ReviewIntent(current, accept, reason);
    await decide();
  }

  Future<void> decide() async {
    final decision = intent;
    if (busy || decision == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final saved = await widget.reviewer.decide(
        decision.view,
        operationId: decision.id,
        accept: decision.accept,
        reason: decision.reason,
      );
      if (mounted) {
        setState(() {
          receipt = saved;
          uncertain = false;
          intent = null;
        });
      }
    } on ProposalReviewFailure catch (failure) {
      // A domain rejection did not apply this command. A new reviewed action
      // gets a new UUID; ambiguous failures retain the complete original intent.
      if (mounted) {
        setState(() {
          message = failure.message;
          changed =
              failure.code == 'stale_context' ||
              failure.code == 'already_decided';
          uncertain = false;
          intent = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          uncertain = true;
          message =
              'The result could not be confirmed. Retry this same decision '
              'to check it safely.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = view;
    // Once decided, display the self-contained immutable receipt rather than
    // live draft fields or a recreated pending file with the same creation key.
    final saved = receipt;
    if (saved != null) return _HistoryPage(receipt: saved);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Review suggested notes')),
        body: page([
          if (busy) const LinearProgressIndicator(),
          if (message != null) notice(message!, error: true),
          if (current != null) ...[
            _contextText(context, current.proposal.context),
            const SizedBox(height: 8),
            Text('Suggested by ${current.proposal.record['actor_id']}'),
            Text(
              'Saved ${displayTime(current.proposal.pendingResult['created_at'] as String)}',
            ),
            if (current.stale || changed)
              notice(
                'The inspection changed after these notes were suggested. '
                'They cannot be applied. Refresh to review the current notes; '
                'you can reject this suggestion with a reason.',
                error: true,
              ),
            _heading(context, 'Current draft notes'),
            _notesBox(
              current.currentNotes.isEmpty
                  ? 'No notes have been saved.'
                  : current.currentNotes.join('\n\n'),
            ),
            _heading(context, 'Suggested replacement notes'),
            _notesBox(current.proposal.notes),
            if (receipt == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Applying replaces the draft notes shown above. '
                'Readings, photos and submitted inspection records stay as they are.',
              ),
              const SizedBox(height: 16),
              if (uncertain)
                FilledButton(
                  onPressed: busy ? null : decide,
                  child: const Text('Retry same decision'),
                )
              else ...[
                FilledButton(
                  onPressed: busy || changed || current.stale
                      ? null
                      : () => confirm(true),
                  child: const Text('Apply to draft notes'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy || changed ? null : () => confirm(false),
                  child: const Text('Reject with reason'),
                ),
              ],
            ],
          ],
          if (receipt == null && !uncertain)
            TextButton.icon(
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh current notes'),
            ),
        ]),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.receipt, required this.onOpen});
  final Json receipt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final proposal = NotesProposal.fromRecord(receipt['proposal'] as Json);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _contextText(context, proposal.context),
            Text(
              receipt['decision'] == 'applied'
                  ? 'Applied to draft notes'
                  : 'Rejected',
            ),
            Text(displayTime(receipt['reviewedAt'] as String)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onOpen,
              child: const Text('View review record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({required this.receipt});
  final Json receipt;

  @override
  Widget build(BuildContext context) {
    final proposal = NotesProposal.fromRecord(receipt['proposal'] as Json);
    return Scaffold(
      appBar: AppBar(title: const Text('Review record')),
      body: page([
        _contextText(context, proposal.context),
        _decisionNotice(receipt),
        Text('Reviewed ${displayTime(receipt['reviewedAt'] as String)}'),
        if (receipt['decision'] == 'rejected') ...[
          _heading(context, 'Reason for rejection'),
          Text(receipt['reason'] as String),
        ],
        _heading(context, 'Reviewed suggested notes'),
        _notesBox(proposal.notes),
        const SizedBox(height: 16),
        const Text(
          'This is the saved review record. Later changes to the draft '
          'do not change it.',
        ),
      ]),
    );
  }
}

Widget _heading(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
);

Widget _contextText(BuildContext context, Json job) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(
      equipmentName(job['equipment']),
      style: Theme.of(context).textTheme.titleLarge,
    ),
    Text(jobTitle(job['job'])),
  ],
);

Widget _notesBox(String notes) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(color: const Color(0xffc8d6cf)),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(notes),
);

Widget _decisionNotice(Json receipt) => notice(
  receipt['decision'] == 'applied'
      ? 'Saved locally. Draft notes updated. Open the inspection to check them, '
            'then submit and review the inspection as usual.'
      : 'Rejected and saved locally. Draft notes are unchanged.',
);

String _failureMessage(Object failure) => failure is ProposalReviewFailure
    ? failure.message
    : 'Suggestions could not be loaded. Your saved work is retained. Try refreshing.';
