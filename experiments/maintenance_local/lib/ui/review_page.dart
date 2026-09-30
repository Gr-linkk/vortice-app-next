import 'package:flutter/material.dart';
import '../lab_store.dart';
import '../model.dart';
import 'common.dart';

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
    } catch (e) {
      message = e.toString().replaceFirst('Bad state: ', '');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.submission, v = p['values'] as Json;
    final receipt = widget.store.receipts
        .where((r) => r['submissionId'] == p['id'])
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Submitted inspection')),
      body: page([
        Text(
          widget.store.workspace!['equipment'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Submitted ${displayTime(p['createdAt'] as String)}'),
        const Text(
          'You are viewing the exact submitted version. Later edits do not change this record.',
        ),
        if (message != null) notice(message!),
        for (final e in checklist.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value),
            subtitle: Text(v[e.key] == 'pass' ? 'Pass' : 'Needs attention'),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Meter reading'),
          subtitle: Text('${v['meter']} ${v['unit']}'),
        ),
        const SizedBox(height: 12),
        Text(
          'Inspection notes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(v['notes'] as String),
        evidenceImage(widget.store, v['photo'] as String),
        if (receipt != null)
          notice(
            receipt['decision'] == 'approved'
                ? 'Approved ${displayTime(receipt['reviewedAt'] as String)}'
                : 'Returned: ${receipt['reason']}',
          )
        else if (widget.store.office)
          FutureBuilder<String?>(
            future: widget.store.approvalProblem(p),
            builder: (c, s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.data != null) notice(s.data!, error: true),
                if (s.hasError) notice(s.error.toString(), error: true),
                FilledButton(
                  onPressed:
                      busy ||
                          s.connectionState != ConnectionState.done ||
                          s.hasError ||
                          s.data != null
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
          notice('Waiting for the computer owner to review this version.'),
      ]),
    );
  }
}
