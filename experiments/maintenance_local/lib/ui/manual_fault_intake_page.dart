import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../lab_store.dart';
import '../manual_fault_intake.dart';
import '../manual_fault_intake_store.dart';
import '../model.dart';
import 'common.dart';
import 'inspection_content.dart';

/// Office entry for manual reports and durable requests awaiting confirmation.
class ManualFaultIntakePage extends StatefulWidget {
  const ManualFaultIntakePage({super.key, required this.store, this.intake});

  final LabStore store;

  /// A trusted adapter over the same real store, also used for lost-reply tests.
  final ManualFaultIntakeStore? intake;

  @override
  State<ManualFaultIntakePage> createState() => _ManualFaultIntakePageState();
}

class _ManualFaultIntakePageState extends State<ManualFaultIntakePage> {
  ManualFaultIntakeStore? _intake;
  List<ManualFaultRecord> _records = [];
  List<FrozenManualFaultCommand> _pending = [];
  String? _error;
  bool _busy = false, _readable = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _readable = false;
      _error = null;
    });
    try {
      widget.store.requireOffice();
      if (widget.store.catalog != null) {
        final intake = _intake ??=
            widget.intake ?? ManualFaultIntakeStore(widget.store);
        final records = await intake.listRecords();
        final pending = await intake.pendingCommands();
        if (mounted) {
          setState(() {
            _records = records.reversed.toList();
            _pending = pending;
          });
        }
      }
      if (mounted) setState(() => _readable = true);
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget destination) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
    if (mounted) await _read();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reported faults')),
        body: page([
          notice('Report and view manual faults on the office computer.'),
        ]),
      );
    }
    final equipment = widget.store.equipment;
    return Scaffold(
      appBar: AppBar(title: const Text('Reported faults')),
      body: page([
        const Text('Record a reported problem against your company equipment.'),
        const SizedBox(height: 12),
        const Text(manualFaultReportedStatus),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('manual-fault-new'),
          onPressed:
              !_readable || _busy || equipment.isEmpty || _pending.isNotEmpty
              ? null
              : () => _open(
                  _ManualFaultForm(store: widget.store, intake: _intake!),
                ),
          icon: const Icon(Icons.add),
          label: const Text('Report a fault'),
        ),
        if (_readable && equipment.isEmpty)
          notice(
            'Create your company and add equipment in preparation before reporting a fault.',
          ),
        TextButton.icon(
          key: const Key('manual-fault-reload'),
          onPressed: _busy ? null : _read,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload reported faults'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) notice(_error!, error: true),
        if (_readable && _pending.isNotEmpty) ...[
          _heading(context, 'Saved request'),
          notice(
            'Resume this saved request before starting another report. Its recording result has not been confirmed.',
          ),
          for (final command in _pending)
            _card([
              _heading(
                context,
                _equipmentName(widget.store, command.equipmentId),
                small: true,
              ),
              Text(_severityLabel(command.severity)),
              const Text('Saved request — recording not confirmed'),
              Text(
                command.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              OutlinedButton(
                key: ValueKey('manual-fault-resume-${command.id}'),
                onPressed: _busy
                    ? null
                    : () => _open(
                        _ManualFaultRequestPage(
                          store: widget.store,
                          intake: _intake!,
                          command: command,
                        ),
                      ),
                child: const Text('Open saved request'),
              ),
            ]),
        ],
        const SizedBox(height: 20),
        _heading(context, 'Recorded faults'),
        if (_readable && _records.isEmpty)
          const Text('No manual faults have been recorded yet.'),
        for (final record in _readable ? _records : <ManualFaultRecord>[])
          _card([
            _heading(
              context,
              _equipmentName(widget.store, record.equipmentId),
              small: true,
            ),
            Text(_severityLabel(record.severity)),
            const Text(manualFaultReportedStatus),
            Text('Reported ${displayTime(record.reportedAt)}'),
            const SizedBox(height: 8),
            Text(
              record.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            TextButton(
              key: ValueKey('manual-fault-open-${record.id}'),
              onPressed: _busy
                  ? null
                  : () => _open(
                      _ManualFaultRecordPage(
                        store: widget.store,
                        record: record,
                      ),
                    ),
              child: const Text('View fault record'),
            ),
          ]),
      ]),
    );
  }
}

class _ManualFaultForm extends StatefulWidget {
  const _ManualFaultForm({required this.store, required this.intake});
  final LabStore store;
  final ManualFaultIntakeStore intake;

  @override
  State<_ManualFaultForm> createState() => _ManualFaultFormState();
}

class _ManualFaultFormState extends State<_ManualFaultForm> {
  final _description = TextEditingController();
  final _commandId = const Uuid().v4();
  String? _equipmentId, _error;
  ManualFaultSeverity _severity = ManualFaultSeverity.normal;
  ManualFaultOrigin? _origin;
  FrozenManualFaultCommand? _command;
  bool _busy = false, _uncertain = false, _dirty = false, _leaving = false;
  bool get _locked => _busy || _uncertain || _command != null;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseEquipment() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _EquipmentPicker(store: widget.store)),
    );
    if (!mounted || id == null || _locked) return;
    setState(() {
      if (_equipmentId != id) _origin = null;
      _equipmentId = id;
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _chooseSource() async {
    final equipment = _equipmentId;
    if (equipment == null || _locked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final origin = await Navigator.push<ManualFaultOrigin>(
      context,
      MaterialPageRoute(
        builder: (_) => _SourcePicker(
          store: widget.store,
          intake: widget.intake,
          equipmentId: equipment,
        ),
      ),
    );
    if (!mounted || origin == null || _locked) return;
    setState(() {
      _origin = origin;
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _leave() async {
    if (_leaving || _busy) return;
    if (!_dirty || _command != null || _uncertain) {
      setState(() => _leaving = true);
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Discard this report?'),
        content: const Text(
          'This report has not been saved. Discard its description and selections?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard report'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> _record() async {
    if (_busy) return;
    if (_equipmentId == null || _description.text.trim().isEmpty) {
      setState(
        () => _error = 'Select equipment and describe the reported problem.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _uncertain = true;
      _error = null;
    });
    try {
      final command =
          _command ??
          await widget.intake.freeze(
            equipmentId: _equipmentId!,
            description: _description.text,
            severity: _severity,
            originSelection: _origin,
            commandId: _commandId,
          );
      _command = command;
      final receipt = await widget.intake.record(command);
      if (!mounted) return;
      setState(() => _leaving = true);
      Navigator.pop(context, receipt.record);
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
      // A failed reply is not proof that freeze failed. Only successful reads
      // of both durable intent and receipt can make an unsaved form editable.
      if (_command == null) await _recover();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    try {
      final pending = await widget.intake.pendingCommands();
      final receipt = await widget.intake.receiptFor(_commandId);
      if (!mounted) return;
      if (receipt != null) {
        setState(() => _leaving = true);
        Navigator.pop(context, receipt.record);
      } else {
        setState(() {
          _command = pending.where((c) => c.id == _commandId).firstOrNull;
          _uncertain = _command != null || pending.isNotEmpty;
          if (pending.isNotEmpty && _command == null) {
            _error =
                'Another saved request needs to be resumed. Return to reported faults and open it.';
          }
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error =
              '${_message(failure)}\nThe recording result could not be checked. Keep this request unchanged and try again.';
        });
      }
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _recover();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving || (!_busy && (!_dirty || _uncertain || _command != null)),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Report a fault')),
      body: page([
        const Text(
          'Describe the problem that was reported. Normal is selected by default.',
        ),
        const SizedBox(height: 20),
        _heading(context, 'Equipment', small: true),
        if (_equipmentId != null)
          Text(_equipmentName(widget.store, _equipmentId!)),
        OutlinedButton(
          key: const Key('manual-fault-equipment'),
          onPressed: _locked ? null : _chooseEquipment,
          child: Text(
            _equipmentId == null ? 'Select equipment' : 'Change equipment',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('manual-fault-description'),
          controller: _description,
          enabled: !_locked,
          minLines: 4,
          maxLines: 8,
          maxLength: 10000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _dirty = true),
          decoration: const InputDecoration(labelText: 'Reported problem'),
        ),
        const SizedBox(height: 12),
        _heading(context, 'Severity', small: true),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final severity in ManualFaultSeverity.values)
              ChoiceChip(
                key: ValueKey('manual-fault-severity-${severity.name}'),
                label: Text(_severityLabel(severity)),
                selected: _severity == severity,
                onSelected: _locked
                    ? null
                    : (_) => setState(() {
                        _severity = severity;
                        _dirty = true;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _heading(context, 'Saved inspection source (optional)', small: true),
        const Text(
          'Link an exact submitted version, step or note if it helps explain this report.',
        ),
        if (_origin != null) ...[
          const SizedBox(height: 12),
          _OriginSummary(store: widget.store, origin: _origin!),
          TextButton(
            key: const Key('manual-fault-clear-source'),
            onPressed: _locked
                ? null
                : () => setState(() {
                    _origin = null;
                    _dirty = true;
                  }),
            child: const Text('Remove source'),
          ),
        ],
        OutlinedButton(
          key: const Key('manual-fault-source'),
          onPressed: _locked || _equipmentId == null ? null : _chooseSource,
          child: Text(
            _origin == null
                ? 'Choose saved inspection source'
                : 'Change saved source',
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) notice(_error!, error: true),
        if (_command != null || _uncertain)
          notice(
            _command != null
                ? 'Saved request — recording not confirmed. Its equipment, description, severity and source are fixed. Resume the same request to confirm its result.'
                : 'The recording result is uncertain. Keep the request unchanged while checking its saved result.',
          ),
        const SizedBox(height: 16),
        if (_command != null)
          FilledButton(
            key: const Key('manual-fault-submit'),
            onPressed: _busy ? null : _record,
            child: const Text('Resume saved request'),
          )
        else if (_uncertain)
          FilledButton(
            key: const Key('manual-fault-check'),
            onPressed: _busy ? null : _check,
            child: const Text('Check saved request'),
          )
        else
          FilledButton(
            key: const Key('manual-fault-submit'),
            onPressed: _busy ? null : _record,
            child: const Text('Record reported fault'),
          ),
        TextButton(
          key: const Key('manual-fault-cancel'),
          onPressed: _busy ? null : _leave,
          child: Text(
            _command != null || _uncertain
                ? 'Back to reported faults'
                : 'Cancel report',
          ),
        ),
      ]),
    ),
  );
}

class _EquipmentPicker extends StatelessWidget {
  const _EquipmentPicker({required this.store});
  final LabStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select equipment')),
    body: page([
      for (final equipment in store.equipment)
        _card([
          _heading(context, equipmentName(equipment), small: true),
          if ((equipment['serial'] ?? '').toString().isNotEmpty)
            Text('Equipment ID: ${equipment['serial']}'),
          TextButton(
            key: ValueKey('manual-fault-equipment-${equipment['id']}'),
            onPressed: () => Navigator.pop(context, equipment['id'] as String),
            child: const Text('Use this equipment'),
          ),
        ]),
    ]),
  );
}

class _ManualFaultRequestPage extends StatefulWidget {
  const _ManualFaultRequestPage({
    required this.store,
    required this.intake,
    required this.command,
  });
  final LabStore store;
  final ManualFaultIntakeStore intake;
  final FrozenManualFaultCommand command;

  @override
  State<_ManualFaultRequestPage> createState() =>
      _ManualFaultRequestPageState();
}

class _ManualFaultRequestPageState extends State<_ManualFaultRequestPage> {
  ManualFaultRecord? _record;
  String? _error;
  bool _busy = false;

  Future<void> _resume() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.intake.record(widget.command);
      if (mounted) setState(() => _record = receipt.record);
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record != null) {
      return _ManualFaultRecordPage(store: widget.store, record: record);
    }
    final command = widget.command;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Saved fault request')),
        body: page([
          notice(
            'Saved request — recording not confirmed. Resume this exact request to confirm its result. Its fields cannot be edited.',
          ),
          _FaultFacts(
            store: widget.store,
            equipmentId: command.equipmentId,
            description: command.description,
            severity: command.severity,
            origin: command.origin,
          ),
          Text('Request saved ${displayTime(command.createdAt)}'),
          if (_error != null) notice(_error!, error: true),
          if (_busy) const LinearProgressIndicator(),
          FilledButton(
            key: const Key('manual-fault-resume-request'),
            onPressed: _busy ? null : _resume,
            child: const Text('Resume saved request'),
          ),
        ]),
      ),
    );
  }
}

class _ManualFaultRecordPage extends StatelessWidget {
  const _ManualFaultRecordPage({required this.store, required this.record});
  final LabStore store;
  final ManualFaultRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fault record')),
    body: page([
      notice(manualFaultReportedStatus),
      Text('Reported ${displayTime(record.reportedAt)}'),
      const SizedBox(height: 16),
      _FaultFacts(
        store: store,
        equipmentId: record.equipmentId,
        description: record.description,
        severity: record.severity,
        origin: record.origin,
      ),
    ]),
  );
}

class _FaultFacts extends StatelessWidget {
  const _FaultFacts({
    required this.store,
    required this.equipmentId,
    required this.description,
    required this.severity,
    required this.origin,
  });
  final LabStore store;
  final String equipmentId, description;
  final ManualFaultSeverity severity;
  final ManualFaultOrigin? origin;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(context, _equipmentName(store, equipmentId)),
      Text('Severity: ${_severityLabel(severity)}'),
      const SizedBox(height: 20),
      _heading(context, 'Reported problem', small: true),
      SelectableText(description),
      const SizedBox(height: 20),
      if (origin != null)
        _OriginSummary(store: store, origin: origin!)
      else
        const Text('No inspection source was linked.'),
    ],
  );
}

class _OriginSummary extends StatelessWidget {
  const _OriginSummary({required this.store, required this.origin});
  final LabStore store;
  final ManualFaultOrigin origin;

  @override
  Widget build(BuildContext context) => _card([
    _heading(context, 'Saved inspection source', small: true),
    Text(origin.label),
    Text('Captured observation: ${_observation(origin.observation)}'),
    TextButton(
      key: const Key('manual-fault-view-source'),
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => _SavedSourcePage(store: store, origin: origin),
        ),
      ),
      child: const Text('View saved source'),
    ),
  ]);
}

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({
    required this.store,
    required this.intake,
    required this.equipmentId,
  });
  final LabStore store;
  final ManualFaultIntakeStore intake;
  final String equipmentId;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  List<ManualFaultOrigin> _origins = [];
  String? _error;
  bool _busy = false, _readable = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _readable = false;
      _error = null;
    });
    try {
      final origins = await widget.intake.availableOrigins(widget.equipmentId);
      if (mounted) {
        setState(() {
          _origins = origins;
          _readable = true;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(List<ManualFaultOrigin> origins) async {
    final selected = await Navigator.push<ManualFaultOrigin>(
      context,
      MaterialPageRoute(
        builder: (_) => _SavedSourcePage(
          store: widget.store,
          origin: origins.first,
          choices: origins,
        ),
      ),
    );
    if (mounted && selected != null) Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ManualFaultOrigin>>{};
    for (final origin in _origins) {
      groups.putIfAbsent(origin.submissionId, () => []).add(origin);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Saved inspection source')),
      body: page([
        Text(_equipmentName(widget.store, widget.equipmentId)),
        const SizedBox(height: 12),
        const Text(
          'Choose an exact saved submitted version. Open it to choose the whole version, a step or its notes.',
        ),
        TextButton(
          onPressed: _busy ? null : _read,
          child: const Text('Reload saved sources'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) notice(_error!, error: true),
        if (_readable && groups.isEmpty)
          notice(
            'This equipment has no saved submitted inspections. You can report a fault without a source.',
          ),
        for (final origins
            in _readable ? groups.values : <List<ManualFaultOrigin>>[])
          _card([
            _heading(context, origins.first.label, small: true),
            Text(
              'Submitted device version ${origins.first.submissionRevision}',
            ),
            Text('Observation: ${_observation(origins.first.observation)}'),
            OutlinedButton(
              key: ValueKey(
                'manual-fault-source-${origins.first.submissionId}',
              ),
              onPressed: _busy ? null : () => _open(origins),
              child: const Text('View and choose source'),
            ),
          ]),
      ]),
    );
  }
}

/// The original submitted context is read without opening an editable draft or
/// the decision-capable ReviewPage, and without selecting another inspection.
class _SavedSourcePage extends StatelessWidget {
  const _SavedSourcePage({
    required this.store,
    required this.origin,
    this.choices = const [],
  });
  final LabStore store;
  final ManualFaultOrigin origin;
  final List<ManualFaultOrigin> choices;

  Widget _choose(
    BuildContext context,
    ManualFaultOriginKind kind, {
    String? itemId,
  }) {
    final choice = choices
        .where((o) => o.kind == kind && o.itemId == itemId)
        .firstOrNull;
    if (choice == null) return const SizedBox.shrink();
    return OutlinedButton(
      key: ValueKey(
        'manual-fault-use-${kind.name}${itemId == null ? '' : '-$itemId'}',
      ),
      onPressed: () => Navigator.pop(context, choice),
      child: Text(switch (kind) {
        ManualFaultOriginKind.submission =>
          'Use this submitted version as source',
        ManualFaultOriginKind.item => 'Use this step as source',
        ManualFaultOriginKind.note => 'Use inspection notes as source',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    Json? source, receipt;
    String? error;
    try {
      store.requireOffice();
      final saved = store.submissions
          .where((s) => s['id'] == origin.submissionId)
          .firstOrNull;
      if (saved == null) {
        throw StateError(
          'This saved inspection source is unavailable. Its reference has been retained. Reload reported faults or use the matching workspace backup.',
        );
      }
      source = Map<String, dynamic>.from(saved)..remove('_state');
      if (contentHash(source) != origin.submissionHash) {
        throw StateError(
          'The saved inspection source does not match this reference. Its files have been retained. Reload reported faults or restore the matching workspace backup.',
        );
      }
      if (origin.receiptId != null) {
        receipt = store.receipts
            .where((r) => r['id'] == origin.receiptId)
            .firstOrNull;
        if (receipt == null || contentHash(receipt) != origin.receiptHash) {
          throw StateError(
            'The saved source review does not match this reference. Its files have been retained. Reload reported faults or use the matching workspace backup.',
          );
        }
      }
    } catch (failure) {
      error = _message(failure);
    }
    if (error != null || source == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved inspection source')),
        body: page([
          notice(
            error ??
                'The saved source could not be read. Reload reported faults to try again.',
            error: true,
          ),
        ]),
      );
    }
    final submittedContext = jsonMap(source['context']);
    final values = jsonMap(source['values']);
    final snapshot = jsonMap(submittedContext['checklistSnapshot']);
    final provenance = jsonMap(snapshot['provenance']);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved inspection source')),
      body: page([
        _heading(context, equipmentName(submittedContext['equipment'])),
        _heading(context, jobTitle(submittedContext['job']), small: true),
        Text('Submitted device version ${source['submissionRevision']}'),
        Text('Submitted ${displayTime(source['createdAt'] as String)}'),
        notice('Captured observation: ${_observation(origin.observation)}'),
        const Text(
          'This is the exact saved submitted version. Later edits or reviews do not change the captured observation.',
        ),
        if (receipt != null &&
            origin.observation == ManualFaultObservation.returned)
          notice('Return reason: ${receipt['reason']}'),
        if (choices.isEmpty) ...[
          const SizedBox(height: 12),
          Text('Linked source: ${origin.label}'),
        ],
        const SizedBox(height: 16),
        _choose(context, ManualFaultOriginKind.submission),
        _heading(
          context,
          '${snapshot['title']} · checklist v${snapshot['version']}',
          small: true,
        ),
        for (final item in inspectionItems(submittedContext))
          _card([
            _heading(context, item['label'] as String, small: true),
            Text(stepDefinition(item)),
            const SizedBox(height: 8),
            Text(answerSummary(values['answer:${item['id']}'], item)),
            _choose(
              context,
              ManualFaultOriginKind.item,
              itemId: item['id'] as String,
            ),
          ]),
        const SizedBox(height: 16),
        _heading(context, 'Inspection notes', small: true),
        SelectableText((values['notes'] ?? '').toString()),
        _choose(context, ManualFaultOriginKind.note),
        if (values['photo'] is String)
          _SavedEvidence(store: store, hash: values['photo'] as String),
        if (submittedContext['meterRequired'] == true)
          Text(
            'Meter reading: ${values['meter']} ${meterUnitLabel(submittedContext['meterUnit'])}',
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Prepared checklist and source'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (provenance['kind']) {
              'company-authored' => 'Company-authored procedure',
              'local-reference' => 'Local reference',
              'manual-reference' => 'Manual reference',
              _ => 'Recorded source',
            }),
            if ((provenance['reference'] ?? '').toString().isNotEmpty)
              Text(provenance['reference'].toString()),
            const SizedBox(height: 8),
            const Text(
              'These definitions and source notes were saved when the inspection was prepared.',
            ),
            const SizedBox(height: 8),
            SelectableText('Checklist snapshot: ${origin.snapshotHash}'),
            SelectableText('Submitting device: ${source['device']}'),
          ],
        ),
      ]),
    );
  }
}

class _SavedEvidence extends StatelessWidget {
  const _SavedEvidence({required this.store, required this.hash});
  final LabStore store;
  final String hash;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: store.evidence.complete(hash),
    builder: (context, state) {
      if (state.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Checking saved inspection photo…'),
        );
      }
      if (state.hasError || state.data != true) {
        return notice(
          'The saved inspection photo is unavailable on this computer. Its source reference is retained.',
          error: true,
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Image.file(
          store.evidence.file(hash),
          height: 220,
          fit: BoxFit.contain,
          semanticLabel: 'Saved inspection evidence photo',
          errorBuilder: (_, error, stack) => notice(
            'This saved evidence file cannot be displayed as a photo.',
            error: true,
          ),
        ),
      );
    },
  );
}

Widget _heading(BuildContext context, String text, {bool small = false}) =>
    Text(
      text,
      style: small
          ? Theme.of(context).textTheme.titleMedium
          : Theme.of(context).textTheme.titleLarge,
    );
Widget _card(List<Widget> children) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  ),
);
String _equipmentName(LabStore store, String id) => equipmentName(
  store.equipment.where((e) => e['id'] == id).firstOrNull ??
      'Recorded equipment',
);
String _severityLabel(ManualFaultSeverity severity) =>
    severity == ManualFaultSeverity.urgent ? 'Urgent' : 'Normal';
String _observation(ManualFaultObservation observation) =>
    switch (observation) {
      ManualFaultObservation.pending => 'Pending office review',
      ManualFaultObservation.approved => 'Approved',
      ManualFaultObservation.returned => 'Returned',
    };
String _message(Object failure) =>
    failure.toString().replaceFirst('Bad state: ', '');
