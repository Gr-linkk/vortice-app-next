import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../corrective_planning.dart';
import '../corrective_planning_store.dart';
import '../lab_store.dart';
import '../manual_fault_intake.dart';
import '../manual_fault_intake_store.dart';
import 'common.dart';
import 'inspection_content.dart';

const correctivePlanningNotice =
    'Planning only — work execution is not available.';
const correctivePlanningEditionNotice =
    'Saved corrective planning, this workspace and its backups need this edition of Local Maintenance.';
String correctiveFaultCount(int count, {bool linked = false}) =>
    '$count ${linked ? 'linked ' : ''}reported ${count == 1 ? 'fault' : 'faults'}';

String correctivePlanningMessage(Object failure) =>
    failure is CorrectivePlanningFailure
    ? failure.message
    : 'This planning result could not be confirmed. Your saved work has been retained.';

enum CorrectiveEditorMode { create, edit, link }

class CorrectiveWorkEditorPage extends StatefulWidget {
  const CorrectiveWorkEditorPage({
    super.key,
    required this.store,
    required this.planning,
    required this.mode,
    this.draft,
    this.initialFaultIds = const [],
  });
  final LabStore store;
  final CorrectivePlanningStore planning;
  final CorrectiveEditorMode mode;
  final CorrectiveWorkDraft? draft;
  final List<String> initialFaultIds;

  @override
  State<CorrectiveWorkEditorPage> createState() =>
      _CorrectiveWorkEditorPageState();
}

class _CorrectiveWorkEditorPageState extends State<CorrectiveWorkEditorPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _description = TextEditingController();
  final _commandId = const Uuid().v4();
  final _selected = <String>{};
  List<ManualFaultRecord> _faults = [];
  Set<String> _linked = {};
  CorrectiveWorkDraft? _draft;
  FrozenCorrectivePlanningCommand? _command;
  String? _equipmentId, _error;
  bool _busy = false, _readable = false, _dirty = false;
  bool _uncertain = false, _leaving = false, _otherPending = false;
  bool get _locked => _busy || _uncertain || _command != null || _leaving;
  bool get _create => widget.mode == CorrectiveEditorMode.create;
  bool get _link => widget.mode == CorrectiveEditorMode.link;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _equipmentId = _draft?.equipmentId;
    _title.text = _draft?.title ?? '';
    _description.text = _draft?.description ?? '';
    _selected.addAll(widget.initialFaultIds);
    _read();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!widget.store.office || _busy) return;
    setState(() => _busy = true);
    try {
      final faults = await ManualFaultIntakeStore(widget.store).listRecords();
      final drafts = await widget.planning.listDrafts();
      final pending = await widget.planning.pendingCommands();
      if (!mounted) return;
      final linked = {
        for (final draft in drafts)
          for (final ref in draft.faults) ref.faultId,
      };
      if (_create && widget.initialFaultIds.isNotEmpty) {
        final initial = faults
            .where((f) => f.id == widget.initialFaultIds.first)
            .firstOrNull;
        if (initial == null || linked.contains(initial.id)) {
          throw const CorrectivePlanningFailure(
            'invalid_fault',
            'This fault already has a plan or is unavailable. Reload corrective planning.',
          );
        }
        _equipmentId = initial.equipmentId;
      }
      setState(() {
        _faults = faults;
        _linked = linked;
        _otherPending = pending.isNotEmpty;
        _readable = true;
        _error = null;
      });
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseEquipment() async {
    if (_locked || widget.initialFaultIds.isNotEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _CorrectiveEquipmentPicker(store: widget.store),
      ),
    );
    if (!mounted || id == null || _locked || id == _equipmentId) return;
    if (_selected.isNotEmpty) {
      final change = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Change equipment?'),
          content: const Text(
            'The selected faults will be cleared. Your title and planning description will stay here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep selection'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Change equipment'),
            ),
          ],
        ),
      );
      if (!mounted || change != true || _locked) return;
    }
    setState(() {
      _equipmentId = id;
      _selected.clear();
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _leave() async {
    if (_busy || _leaving) return;
    if (_dirty && _command == null && !_uncertain) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('Discard unsaved planning changes?'),
          content: const Text(
            'Your saved work stays unchanged. These unsaved selections and instructions will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _recover() async {
    try {
      final receipt = await widget.planning.receiptFor(_commandId);
      final pending = await widget.planning.pendingCommands();
      if (!mounted) return;
      setState(() {
        _command =
            receipt?.command ??
            pending.where((c) => c.id == _commandId).firstOrNull;
        if (_command != null) _adoptCommand(_command!);
        _uncertain = false;
        _otherPending = pending.any((c) => c.id != _commandId);
      });
    } catch (_) {
      if (mounted) setState(() => _uncertain = true);
    }
  }

  void _adoptCommand(FrozenCorrectivePlanningCommand command) {
    _command = command;
    _equipmentId = command.equipmentId;
    if (command.title != null) _title.text = command.title!;
    if (command.description != null) _description.text = command.description!;
    if (command.action != CorrectivePlanningAction.edit) {
      _selected
        ..clear()
        ..addAll(command.faults.map((ref) => ref.faultId));
    }
  }

  Future<void> _recheck() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _recover();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_locked || !_readable || _otherPending) return;
    if (!_link && !_form.currentState!.validate()) return;
    if (_equipmentId == null || (_link && _selected.isEmpty)) {
      setState(
        () => _error = _equipmentId == null
            ? 'Choose existing equipment for this draft.'
            : 'Select at least one reported fault to link.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final command = switch (widget.mode) {
        CorrectiveEditorMode.create => await widget.planning.freezeCreate(
          equipmentId: _equipmentId!,
          title: _title.text,
          description: _description.text,
          faultIds: _selected.toList(),
          commandId: _commandId,
        ),
        CorrectiveEditorMode.edit => await widget.planning.freezeEdit(
          draftId: _draft!.id,
          expectedRevision: _draft!.revision,
          expectedDraftHash: _draft!.hash,
          title: _title.text,
          description: _description.text,
          commandId: _commandId,
        ),
        CorrectiveEditorMode.link => await widget.planning.freezeLink(
          draftId: _draft!.id,
          expectedRevision: _draft!.revision,
          expectedDraftHash: _draft!.hash,
          faultIds: _selected.toList(),
          commandId: _commandId,
        ),
      };
      _adoptCommand(command);
      await widget.planning.apply(command);
      if (mounted) _finish(command.draftId);
    } catch (failure) {
      if (_command == null) await _recover();
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(String draftId) {
    setState(() {
      _dirty = false;
      _leaving = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, draftId);
    });
  }

  Future<void> _resume() async {
    if (_busy || _command == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.planning.apply(_command!);
      if (mounted) _finish(_command!.draftId);
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadRevision() async {
    if (_locked || _draft == null) return;
    setState(() => _busy = true);
    try {
      final latest = await widget.planning.draftFor(_draft!.id);
      if (latest == null) {
        throw const CorrectivePlanningFailure(
          'invalid_draft',
          'This saved corrective draft is unavailable.',
        );
      }
      if (mounted) {
        setState(() {
          _draft = latest;
          _error = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = switch (widget.mode) {
      CorrectiveEditorMode.create => 'Create corrective draft',
      CorrectiveEditorMode.edit => 'Edit planning details',
      CorrectiveEditorMode.link => 'Link reported faults',
    };
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: Text(heading)),
        body: page([notice('Plan corrective work on the office computer.')]),
      );
    }
    final equipment = widget.store.equipment
        .where((e) => e['id'] == _equipmentId)
        .firstOrNull;
    final choices = _faults.where(
      (f) => f.equipmentId == _equipmentId && !_linked.contains(f.id),
    );
    return PopScope(
      canPop:
          _leaving || (!_dirty && !_busy && !_uncertain && _command == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(heading)),
        body: Form(
          key: _form,
          child: page([
            notice(correctivePlanningNotice),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) notice(_error!, error: true),
            if (_otherPending)
              notice(
                'Resume the saved planning request from Corrective planning before making another change.',
              ),
            if (_uncertain) ...[
              notice(
                'The saved request has not been confirmed. Your fields stay fixed until its original result can be read.',
              ),
              OutlinedButton(
                key: const Key('corrective-recheck'),
                onPressed: _busy ? null : _recheck,
                child: const Text('Recheck saved request'),
              ),
            ],
            if (_command != null) ...[
              notice(
                'This request has been saved. Resume its exact fields to confirm the result.',
              ),
              FilledButton(
                key: const Key('corrective-resume'),
                onPressed: _busy ? null : _resume,
                child: const Text('Resume saved request'),
              ),
            ],
            if (_readable) ...[
              const SizedBox(height: 12),
              Text('Equipment', style: Theme.of(context).textTheme.titleMedium),
              Text(
                equipment == null
                    ? 'Choose existing equipment'
                    : equipmentName(equipment),
              ),
              if (_create && widget.initialFaultIds.isEmpty)
                OutlinedButton(
                  key: const Key('corrective-equipment'),
                  onPressed: _locked ? null : _chooseEquipment,
                  child: const Text('Choose equipment'),
                ),
              if (_draft != null) ...[
                Text(
                  _draft!.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Corrective work · Draft revision ${_draft!.revision}'),
              ],
              const SizedBox(height: 20),
              if (!_link)
                CorrectiveWorkFields(
                  title: _title,
                  description: _description,
                  locked: _locked,
                  titleLimit: correctivePlanningTitleLimit,
                  descriptionLimit: correctivePlanningDescriptionLimit,
                  onChanged: () => setState(() => _dirty = true),
                  titleKey: const Key('corrective-title'),
                  descriptionKey: const Key('corrective-description'),
                ),
              if (_create || _link) ...[
                const SizedBox(height: 20),
                Text(
                  _create
                      ? 'Reported faults (optional)'
                      : 'Reported faults to link',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_create)
                  const Text(
                    'Select faults for this equipment, or save a standalone draft.',
                  ),
                if (_equipmentId != null && choices.isEmpty)
                  notice(
                    'No unlinked reported faults are available for this equipment.',
                  ),
                for (final fault in choices)
                  Card(
                    child: CheckboxListTile(
                      key: ValueKey('corrective-fault-${fault.id}'),
                      contentPadding: const EdgeInsets.all(12),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(fault.description),
                      subtitle: Text(
                        fault.severity == ManualFaultSeverity.urgent
                            ? 'Urgent · Reported'
                            : 'Normal · Reported',
                      ),
                      value: _selected.contains(fault.id),
                      onChanged: _locked
                          ? null
                          : (value) => setState(() {
                              value == true
                                  ? _selected.add(fault.id)
                                  : _selected.remove(fault.id);
                              _dirty = true;
                            }),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('corrective-save'),
                onPressed: _locked || _otherPending ? null : _save,
                child: Text(switch (widget.mode) {
                  CorrectiveEditorMode.create => 'Save corrective draft',
                  CorrectiveEditorMode.edit => 'Save planning changes',
                  CorrectiveEditorMode.link => 'Link selected faults',
                }),
              ),
              if (_draft != null && _error != null && !_locked)
                TextButton(
                  key: const Key('corrective-reload-revision'),
                  onPressed: _reloadRevision,
                  child: const Text(
                    'Reload saved revision · keep unsaved input',
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

class CorrectivePlanningRequestPage extends StatefulWidget {
  const CorrectivePlanningRequestPage({
    super.key,
    required this.store,
    required this.planning,
    required this.command,
  });
  final LabStore store;
  final CorrectivePlanningStore planning;
  final FrozenCorrectivePlanningCommand command;
  @override
  State<CorrectivePlanningRequestPage> createState() =>
      _CorrectivePlanningRequestPageState();
}

class _CorrectivePlanningRequestPageState
    extends State<CorrectivePlanningRequestPage> {
  bool _busy = false;
  bool _reading = false, _readable = false;
  CorrectiveWorkDraft? _draft;
  List<ManualFaultRecord> _faults = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (!widget.store.office || _busy || _reading) return;
    setState(() {
      _reading = true;
      _readable = false;
      _error = null;
    });
    try {
      final draft = await widget.planning.draftFor(widget.command.draftId);
      if (draft == null &&
          widget.command.action != CorrectivePlanningAction.create) {
        throw const CorrectivePlanningFailure(
          'draft_not_found',
          'This saved request needs its original corrective draft. Its saved fields have been retained.',
        );
      }
      final faults = await ManualFaultIntakeStore(widget.store).listRecords();
      if (mounted) {
        setState(() {
          _draft = draft;
          _faults = faults
              .where(
                (fault) =>
                    widget.command.faults.any((ref) => ref.faultId == fault.id),
              )
              .toList();
          _readable = true;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _resume() async {
    if (_busy || !_readable || !widget.store.office) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.planning.apply(widget.command);
      if (mounted) Navigator.pop(context, widget.command.draftId);
    } catch (failure) {
      if (mounted) setState(() => _error = correctivePlanningMessage(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Saved planning request')),
      body: page([
        if (!widget.store.office)
          notice('Plan corrective work on the office computer.')
        else ...[
          notice(correctivePlanningNotice),
          const Text(
            'These original fields are saved. Resume this request to confirm its result.',
          ),
          const SizedBox(height: 12),
          Text(switch (widget.command.action) {
            CorrectivePlanningAction.create => 'Create corrective draft',
            CorrectivePlanningAction.edit => 'Edit planning details',
            CorrectivePlanningAction.link => 'Link reported faults',
          }, style: Theme.of(context).textTheme.titleLarge),
          if (widget.command.equipmentSnapshot != null)
            Text(equipmentName(widget.command.equipmentSnapshot!)),
          if (_draft != null && widget.command.equipmentSnapshot == null)
            Text(equipmentName(_draft!.equipmentSnapshot)),
          if (_draft != null &&
              widget.command.action == CorrectivePlanningAction.link)
            Text(_draft!.title, style: Theme.of(context).textTheme.titleMedium),
          if (widget.command.title != null)
            Text(
              widget.command.title!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (widget.command.description != null)
            Text(widget.command.description!),
          Text(
            '${correctiveFaultCount(widget.command.faults.length)} in this request',
          ),
          for (final fault in _faults)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(fault.description),
                    Text(
                      fault.severity == ManualFaultSeverity.urgent
                          ? 'Urgent · Reported'
                          : 'Normal · Reported',
                    ),
                  ],
                ),
              ),
            ),
          if (widget.command.expectedRevision != null)
            Text('Saved draft revision ${widget.command.expectedRevision}'),
          if (_error != null) notice(_error!, error: true),
          if (_busy || _reading) const LinearProgressIndicator(),
          if (!_readable && !_reading)
            OutlinedButton(
              onPressed: _busy ? null : _read,
              child: const Text('Reload saved request'),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('corrective-request-resume'),
            onPressed: _busy || !_readable ? null : _resume,
            child: const Text('Resume saved request'),
          ),
        ],
      ]),
    ),
  );
}

class _CorrectiveEquipmentPicker extends StatelessWidget {
  const _CorrectiveEquipmentPicker({required this.store});
  final LabStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose equipment')),
    body: page([
      for (final equipment in store.equipment)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  equipmentName(equipment),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((equipment['serial'] as String?)?.isNotEmpty == true)
                  Text(equipment['serial'] as String),
                OutlinedButton(
                  key: ValueKey('corrective-use-equipment-${equipment['id']}'),
                  onPressed: () =>
                      Navigator.pop(context, equipment['id'] as String),
                  child: const Text('Use this equipment'),
                ),
              ],
            ),
          ),
        ),
    ]),
  );
}

/// Shared fields for creating a plan and editing its unstarted instructions.
class CorrectiveWorkFields extends StatelessWidget {
  const CorrectiveWorkFields({
    super.key,
    required this.title,
    required this.description,
    required this.locked,
    required this.titleLimit,
    required this.descriptionLimit,
    required this.onChanged,
    required this.titleKey,
    required this.descriptionKey,
  });

  final TextEditingController title, description;
  final bool locked;
  final int titleLimit, descriptionLimit;
  final VoidCallback onChanged;
  final Key titleKey, descriptionKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: titleKey,
        controller: title,
        enabled: !locked,
        maxLength: titleLimit,
        decoration: const InputDecoration(labelText: 'Title', errorMaxLines: 4),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Enter a title for the corrective work.'
            : null,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: descriptionKey,
        controller: description,
        enabled: !locked,
        minLines: 5,
        maxLines: null,
        maxLength: descriptionLimit,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          labelText: 'Planning description',
          alignLabelWithHint: true,
          errorMaxLines: 4,
        ),
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 8),
      const Text(
        'You can describe the problem, what needs diagnosis and the instructions for future work.',
      ),
    ],
  );
}
