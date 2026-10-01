import 'package:flutter/material.dart';

import '../corrective_planning.dart';
import '../corrective_planning_store.dart';
import '../lab_store.dart';
import '../manual_fault_intake.dart';
import '../manual_fault_intake_store.dart';
import 'common.dart';
import 'corrective_work_editor.dart';
import 'inspection_content.dart';

class CorrectiveWorkDraftPage extends StatefulWidget {
  const CorrectiveWorkDraftPage({
    super.key,
    required this.store,
    required this.draftId,
    this.planning,
  });
  final LabStore store;
  final String draftId;
  final CorrectivePlanningStore? planning;
  @override
  State<CorrectiveWorkDraftPage> createState() =>
      _CorrectiveWorkDraftPageState();
}

class _CorrectiveWorkDraftPageState extends State<CorrectiveWorkDraftPage> {
  late final _planning =
      widget.planning ?? CorrectivePlanningStore(widget.store);
  CorrectiveWorkDraft? _draft;
  List<ManualFaultRecord> _faults = [];
  List<FrozenCorrectivePlanningCommand> _pending = [];
  String? _error;
  bool _busy = false, _readable = false;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (!widget.store.office || _busy) return;
    setState(() {
      _busy = true;
      _readable = false;
      _error = null;
    });
    try {
      final draft = await _planning.draftFor(widget.draftId);
      if (draft == null) {
        throw const CorrectivePlanningFailure(
          'draft_not_found',
          'This corrective draft is unavailable. Return to Corrective planning.',
        );
      }
      final faults = await ManualFaultIntakeStore(widget.store).listRecords();
      final pending = await _planning.pendingCommands();
      if (mounted) {
        setState(() {
          _draft = draft;
          _faults = faults
              .where(
                (fault) => draft.faults.any((ref) => ref.faultId == fault.id),
              )
              .toList();
          _pending = pending;
          _readable = true;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(CorrectiveEditorMode mode) async {
    if (_busy || !_readable || _pending.isNotEmpty) return;
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectiveWorkEditorPage(
          store: widget.store,
          planning: _planning,
          mode: mode,
          draft: _draft,
        ),
      ),
    );
    if (mounted) await _read();
  }

  Future<void> _resume(FrozenCorrectivePlanningCommand command) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectivePlanningRequestPage(
          store: widget.store,
          planning: _planning,
          command: command,
        ),
      ),
    );
    if (mounted) await _read();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: const Text('Corrective work draft')),
        body: page([
          notice('View and plan corrective work on the office computer.'),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Corrective work draft')),
      body: page([
        notice(correctivePlanningNotice),
        const Text(correctivePlanningEditionNotice),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) notice(_error!, error: true),
        TextButton.icon(
          key: const Key('corrective-draft-reload'),
          onPressed: _busy ? null : _read,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload saved draft'),
        ),
        if (_readable && _draft != null) ...[
          Text(_draft!.title, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            equipmentName(_draft!.equipmentSnapshot),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Corrective work · Draft revision ${_draft!.revision}'),
          Text('Saved ${displayTime(_draft!.updatedAt)}'),
          const SizedBox(height: 20),
          Text(
            'Planning description',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            _draft!.description.isEmpty
                ? 'No planning description recorded yet'
                : _draft!.description,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('corrective-edit'),
            onPressed: _busy || _pending.isNotEmpty
                ? null
                : () => _edit(CorrectiveEditorMode.edit),
            child: const Text('Edit planning details'),
          ),
          OutlinedButton(
            key: const Key('corrective-add-faults'),
            onPressed: _busy || _pending.isNotEmpty
                ? null
                : () => _edit(CorrectiveEditorMode.link),
            child: const Text('Link reported faults'),
          ),
          for (final command in _pending) ...[
            notice(
              'Resume the saved planning request before making another change.',
            ),
            OutlinedButton(
              key: ValueKey('corrective-draft-pending-${command.id}'),
              onPressed: _busy ? null : () => _resume(command),
              child: const Text('Open saved request'),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Linked reported faults',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_faults.isEmpty)
            const Text(
              'This is a standalone corrective draft. No reported faults are linked.',
            ),
          for (final fault in _faults)
            Card(
              key: ValueKey('corrective-linked-${fault.id}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Planned · Linked to this corrective draft'),
                    Text(fault.description),
                    Text(
                      fault.severity == ManualFaultSeverity.urgent
                          ? 'Urgent'
                          : 'Normal',
                    ),
                    Text('Reported ${displayTime(fault.reportedAt)}'),
                    const Text('Original report'),
                    const Text('At report: $manualFaultReportedStatus'),
                    if (fault.origin != null) ...[
                      Text('Saved source: ${fault.origin!.label}'),
                      Text(
                        'Observation at report: ${fault.origin!.observation.name}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ]),
    );
  }
}
