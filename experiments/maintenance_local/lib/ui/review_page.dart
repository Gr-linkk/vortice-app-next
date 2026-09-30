import 'package:flutter/material.dart';
import '../lab_store.dart';
import '../model.dart';
import 'common.dart';
import 'inspection_content.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.store,
    required this.submission,
    this.updates,
  });
  final LabStore store;
  final Json submission;
  final Listenable? updates;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  String? message;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(refresh);
  }

  @override
  void didUpdateWidget(covariant ReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      oldWidget.updates?.removeListener(refresh);
      widget.updates?.addListener(refresh);
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.updates?.removeListener(refresh);
    super.dispose();
  }

  Future<void> decide(bool approved) async {
    String reason = '';
    if (!approved) {
      final value = await askText(
        context,
        'Return for changes',
        'Reason for return',
        multiline: true,
      );
      if (value == null) return;
      reason = value;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await widget.store.decide(
        widget.submission['id'] as String,
        approve: approved,
        reason: reason,
      );
      message = approved
          ? 'This version is approved and saved.'
          : 'Returned with your reason.';
    } catch (failure) {
      message = failure.toString().replaceFirst('Bad state: ', '');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission,
        values = jsonMap(submission['values']);
    final submittedContext = jsonMap(submission['context']);
    final legacy = submittedContext.isEmpty;
    // Legacy lab submissions predate frozen context. Real jobs always render
    // their submitted context, never the currently selected job or catalog.
    final job = legacy ? jsonMap(widget.store.workspace) : submittedContext;
    final equipment = jsonMap(job['equipment']);
    final snapshot = jsonMap(job['checklistSnapshot']);
    final items = inspectionItems(job);
    final flags = items
        .where(
          (item) => [
            'action',
            'attention',
          ].contains(jsonMap(values['answer:${item['id']}'])['result']),
        )
        .length;
    final receipt = widget.store.receipts
        .where((r) => r['submissionId'] == submission['id'])
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Submitted inspection')),
      body: page([
        Text(
          equipmentName(job['equipment']),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (!legacy) ...[
          Text(
            jobTitle(job['job']),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text((job['company'] ?? '').toString()),
          if ((equipment['serial'] ?? '').toString().isNotEmpty)
            Text('Equipment ID: ${equipment['serial']}'),
          Text('Submitted version ${submission['submissionRevision'] ?? 1}'),
        ],
        Text('Submitted ${displayTime(submission['createdAt'] as String)}'),
        const SizedBox(height: 12),
        const Text(
          'You are viewing the exact submitted version. Later edits do not change this record.',
        ),
        if (!legacy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Approval acknowledges this inspection record. It does not mark repairs complete or change equipment availability.',
            ),
          ),
        if (message != null) notice(message!),
        if (!legacy && flags > 0)
          notice(
            '$flags ${flags == 1 ? 'step needs' : 'steps need'} action. Review the findings and notes before deciding.',
          ),
        if (legacy)
          for (final entry in checklist.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              subtitle: Text(
                values[entry.key] == 'pass' ? 'Pass' : 'Needs attention',
              ),
            )
        else ...[
          const SizedBox(height: 16),
          Text(
            '${snapshot['title']} · checklist v${snapshot['version']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item['label'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(stepDefinition(item)),
                    const SizedBox(height: 8),
                    Text(
                      answerSummary(values['answer:${item['id']}'], item),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (legacy || job['meterRequired'] == true)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Meter reading'),
            subtitle: Text(
              '${values['meter'] ?? 'Not recorded'} ${legacy ? values['unit'] ?? 'hours' : meterUnitLabel(job['meterUnit'])}',
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Equipment meter: none'),
          ),
        const SizedBox(height: 12),
        Text(
          'Inspection notes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text((values['notes'] ?? '').toString()),
        if (values['photo'] is String)
          evidenceImage(widget.store, values['photo'] as String),
        if (!legacy) snapshotDetails(snapshot, job, submission),
        if (receipt != null) ...[
          notice(
            receipt['decision'] == 'approved'
                ? 'Approved ${displayTime(receipt['reviewedAt'] as String)}'
                : 'Returned: ${receipt['reason']}',
          ),
          Text(
            'Reviewed by ${receipt['reviewedBy'] ?? job['coordinatorName'] ?? 'Office coordinator'}',
          ),
          const SizedBox(height: 8),
          const Text(
            'This decision is saved with this version. Any corrections must be submitted as a new version.',
          ),
        ] else if (widget.store.office)
          FutureBuilder<String?>(
            future: widget.store.approvalProblem(submission),
            builder: (c, state) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.data != null) notice(state.data!, error: true),
                if (state.hasError) notice(state.error.toString(), error: true),
                FilledButton(
                  onPressed:
                      busy ||
                          state.connectionState != ConnectionState.done ||
                          state.hasError ||
                          state.data != null
                      ? null
                      : () => decide(true),
                  child: const Text('Approve this version'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => decide(false),
                  child: const Text('Return with a reason'),
                ),
              ],
            ),
          )
        else
          notice('Waiting for the office coordinator to review this version.'),
      ]),
    );
  }

  Widget snapshotDetails(Json snapshot, Json job, Json submission) {
    final provenance = jsonMap(snapshot['provenance']);
    final kind = provenance['kind'];
    final source = switch (kind) {
      'company-authored' => 'Company-authored procedure',
      'local-reference' => 'Local reference',
      'manual-reference' => 'Manual reference',
      _ => 'Recorded source',
    };
    return Card(
      child: ExpansionTile(
        title: const Text('Prepared checklist and source'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(source),
          if ((provenance['reference'] ?? '').toString().isNotEmpty)
            Text(provenance['reference'].toString()),
          const SizedBox(height: 8),
          const Text(
            'These definitions and source notes were saved when the inspection was prepared. Source notes are not a certification or a verified manufacturer procedure.',
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Checklist snapshot: ${submission['snapshotHash'] ?? job['snapshotHash']}',
          ),
          Text(
            'Prepared revision: ${submission['revision'] ?? job['revision']}',
          ),
          if (submission['predecessorId'] != null)
            SelectableText(
              'Previous submitted version: ${submission['predecessorId']}',
            ),
        ],
      ),
    );
  }
}
