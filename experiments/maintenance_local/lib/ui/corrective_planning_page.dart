import 'package:flutter/material.dart';

import '../corrective_planning.dart';
import '../corrective_planning_store.dart';
import '../lab_store.dart';
import '../manual_fault_intake.dart';
import '../manual_fault_intake_store.dart';
import 'common.dart';
import 'corrective_work_draft_page.dart';
import 'corrective_work_editor.dart';
import 'inspection_content.dart';

class CorrectivePlanningPage extends StatefulWidget {
  const CorrectivePlanningPage({
    super.key,
    required this.store,
    this.initialFaultId,
    this.planning,
  });
  final LabStore store;
  final String? initialFaultId;

  /// A trusted adapter over the same workspace, also used for lost-reply tests.
  final CorrectivePlanningStore? planning;
  @override
  State<CorrectivePlanningPage> createState() => _CorrectivePlanningPageState();
}

class _CorrectivePlanningPageState extends State<CorrectivePlanningPage> {
  late final _planning =
      widget.planning ?? CorrectivePlanningStore(widget.store);
  List<CorrectiveWorkDraft> _drafts = [];
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
      final drafts = await _planning.listDrafts();
      final faults = await ManualFaultIntakeStore(widget.store).listRecords();
      final pending = await _planning.pendingCommands();
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _faults = faults.reversed.toList();
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

  CorrectiveWorkDraft? _draftForFault(String id) => _drafts
      .where((draft) => draft.faults.any((ref) => ref.faultId == id))
      .firstOrNull;

  Future<void> _openDraft(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectiveWorkDraftPage(
          store: widget.store,
          draftId: id,
          planning: _planning,
        ),
      ),
    );
    if (mounted) await _read();
  }

  Future<void> _editor({
    ManualFaultRecord? fault,
    CorrectiveWorkDraft? draft,
  }) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectiveWorkEditorPage(
          store: widget.store,
          planning: _planning,
          mode: draft == null
              ? CorrectiveEditorMode.create
              : CorrectiveEditorMode.link,
          draft: draft,
          initialFaultIds: [if (fault != null) fault.id],
        ),
      ),
    );
    if (!mounted) return;
    await _read();
    if (mounted && id != null) await _openDraft(id);
  }

  Future<void> _linkExisting(ManualFaultRecord fault) async {
    final selected = await Navigator.push<CorrectiveWorkDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => _ExistingDraftPicker(
          drafts: _drafts
              .where(
                (draft) =>
                    draft.equipmentId == fault.equipmentId &&
                    draft.kind == 'corrective' &&
                    draft.state == 'draft',
              )
              .toList(),
        ),
      ),
    );
    if (mounted && selected != null) {
      await _editor(fault: fault, draft: selected);
    }
  }

  Future<void> _request(FrozenCorrectivePlanningCommand command) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CorrectivePlanningRequestPage(
          store: widget.store,
          planning: _planning,
          command: command,
        ),
      ),
    );
    if (!mounted) return;
    await _read();
    if (mounted && id != null) await _openDraft(id);
  }

  Widget _faultCard(ManualFaultRecord fault) {
    final draft = _draftForFault(fault.id);
    final equipment = widget.store.equipment
        .where((e) => e['id'] == fault.equipmentId)
        .firstOrNull;
    final enabled = !_busy && _pending.isEmpty;
    return Card(
      key: ValueKey('corrective-reported-${fault.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              equipment == null
                  ? 'Equipment unavailable'
                  : equipmentName(equipment),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (draft != null) ...[
              const Text('Planned · Corrective draft'),
              Text(draft.title),
            ],
            Text(
              fault.severity == ManualFaultSeverity.urgent
                  ? 'Urgent'
                  : 'Normal',
            ),
            Text(fault.description),
            Text(
              draft == null
                  ? manualFaultReportedStatus
                  : 'At report: $manualFaultReportedStatus',
            ),
            if (draft != null)
              FilledButton(
                key: ValueKey('corrective-open-fault-${fault.id}'),
                onPressed: _busy ? null : () => _openDraft(draft.id),
                child: const Text('Open corrective draft'),
              )
            else ...[
              FilledButton(
                key: ValueKey('corrective-plan-fault-${fault.id}'),
                onPressed: enabled ? () => _editor(fault: fault) : null,
                child: const Text('Create corrective draft'),
              ),
              OutlinedButton(
                key: ValueKey('corrective-existing-fault-${fault.id}'),
                onPressed: enabled ? () => _linkExisting(fault) : null,
                child: const Text('Link to existing corrective draft'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: const Text('Corrective planning')),
        body: page([notice('Plan corrective work on the office computer.')]),
      );
    }
    final initial = _faults
        .where((fault) => fault.id == widget.initialFaultId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Corrective planning')),
      body: page([
        const Text(
          'Save corrective work instructions for existing equipment and link reported faults when needed.',
        ),
        notice(correctivePlanningNotice),
        const Text(correctivePlanningEditionNotice),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) notice(_error!, error: true),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('corrective-new'),
          onPressed:
              !_readable ||
                  _busy ||
                  _pending.isNotEmpty ||
                  widget.store.equipment.isEmpty
              ? null
              : () => _editor(),
          icon: const Icon(Icons.add),
          label: const Text('Create corrective draft'),
        ),
        if (_readable && widget.store.equipment.isEmpty)
          notice(
            'Add company equipment in preparation before planning corrective work.',
          ),
        TextButton.icon(
          key: const Key('corrective-reload'),
          onPressed: _busy ? null : _read,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload corrective planning'),
        ),
        if (_readable) ...[
          for (final command in _pending)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Saved planning request',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Resume the original request before making another planning change.',
                    ),
                    if (command.title != null) Text(command.title!),
                    OutlinedButton(
                      key: ValueKey('corrective-pending-${command.id}'),
                      onPressed: _busy ? null : () => _request(command),
                      child: const Text('Open saved request'),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.initialFaultId != null) ...[
            const SizedBox(height: 20),
            Text(
              'Selected reported fault',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (initial == null)
              notice(
                'This reported fault is unavailable. Reload and choose an existing report.',
                error: true,
              )
            else
              _faultCard(initial),
          ],
          const SizedBox(height: 20),
          Text(
            'Corrective work drafts',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_drafts.isEmpty)
            const Text('No corrective drafts have been saved yet.'),
          for (final draft in _drafts.reversed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      draft.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(equipmentName(draft.equipmentSnapshot)),
                    Text('Corrective work · Draft revision ${draft.revision}'),
                    Text(
                      correctiveFaultCount(draft.faults.length, linked: true),
                    ),
                    TextButton(
                      key: ValueKey('corrective-open-${draft.id}'),
                      onPressed: _busy ? null : () => _openDraft(draft.id),
                      child: const Text('Open corrective draft'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Reported faults',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_faults.isEmpty)
            const Text('No manual faults have been reported yet.'),
          for (final fault in _faults.where(
            (f) => f.id != widget.initialFaultId,
          ))
            _faultCard(fault),
        ],
      ]),
    );
  }
}

class _ExistingDraftPicker extends StatelessWidget {
  const _ExistingDraftPicker({required this.drafts});
  final List<CorrectiveWorkDraft> drafts;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose corrective draft')),
    body: page([
      const Text(
        'Only open corrective drafts for this equipment can be linked.',
      ),
      if (drafts.isEmpty)
        notice(
          'No eligible corrective draft is available for this equipment. Go back to create one.',
        ),
      for (final draft in drafts)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  draft.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(equipmentName(draft.equipmentSnapshot)),
                Text(
                  'Draft revision ${draft.revision} · ${draft.faults.length} linked faults',
                ),
                if (draft.description.isNotEmpty)
                  Text(
                    draft.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                OutlinedButton(
                  key: ValueKey('corrective-use-draft-${draft.id}'),
                  onPressed: () => Navigator.pop(context, draft),
                  child: const Text('Use this corrective draft'),
                ),
              ],
            ),
          ),
        ),
    ]),
  );
}
