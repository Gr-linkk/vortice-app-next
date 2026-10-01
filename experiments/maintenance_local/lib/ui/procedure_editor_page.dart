import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../lab_store.dart';
import '../model.dart';
import '../procedure_library.dart';
import '../procedure_library_store.dart';
import 'common.dart';

/// Edits a saved independent copy; it cannot modify its source publication.
class ProcedureEditorPage extends StatefulWidget {
  const ProcedureEditorPage({
    super.key,
    required this.store,
    required this.draft,
  });

  final LabStore store;
  final Json draft;

  @override
  State<ProcedureEditorPage> createState() => _ProcedureEditorPageState();
}

class _ProcedureEditorPageState extends State<ProcedureEditorPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _steps = <_StepEditor>[];
  final _retired = <_StepEditor>[];
  Json? _draft;
  _SaveRequest? _saveRequest;
  String? _publishOperation, _error, _message;
  bool _busy = false, _dirty = false, _stale = false;

  bool get _finalized => _draft?['publishedTemplateId'] != null;
  bool get _editable => widget.store.office && !_finalized && !_busy;

  @override
  void initState() {
    super.initState();
    if (!widget.store.office) return;
    try {
      _load(widget.draft);
    } catch (failure) {
      _error = _failureMessage(failure);
    }
  }

  void _load(Json draft) {
    validateProcedureDraft(draft);
    _draft = jsonDecode(canonical(draft)) as Json;
    _title.text = draft['title'] as String;
    _retired.addAll(_steps);
    _steps
      ..clear()
      ..addAll(
        (draft['items'] as List).map(
          (item) => _StepEditor(Map<String, dynamic>.from(item as Map)),
        ),
      );
    _dirty = false;
    _stale = false;
    _saveRequest = null;
    _publishOperation = null;
    _error = null;
  }

  void _changed() => setState(() {
    _dirty = true;
    _saveRequest = null;
    _publishOperation = null;
    _message = null;
    if (!_stale) _error = null;
  });

  @override
  void dispose() {
    _title.dispose();
    for (final step in [..._steps, ..._retired]) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Keep editing?'),
        content: const Text(
          'Your latest changes have not been saved. '
          'The saved copy will remain in the library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _reload() async {
    if (_busy || _draft == null) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Reload saved draft?'),
          content: const Text(
            'Reloading replaces the unsaved changes on this '
            'screen with the latest saved copy. Your source checklist stays intact.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              key: const Key('procedure-confirm-reload'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reload saved draft'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    try {
      final saved = widget.store.procedureDrafts
          .where((draft) => draft['id'] == _draft!['id'])
          .firstOrNull;
      if (saved == null) {
        throw StateError(
          'This saved copy is unavailable. Return to the library.',
        );
      }
      setState(() {
        _load(saved);
        _message = 'Latest saved draft loaded.';
      });
    } catch (failure) {
      if (mounted) setState(() => _error = _failureMessage(failure));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _saveRequest ??= _SaveRequest(
      id: const Uuid().v4(),
      revision: _draft!['revision'] as int,
      title: _title.text.trim(),
      items: _steps.map((step) => step.value()).toList(),
    );
    final request = _saveRequest!;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final saved = await widget.store.saveProcedureDraft(
        draftId: _draft!['id'] as String,
        expectedRevision: request.revision,
        title: request.title,
        items: request.items,
        operationId: request.id,
      );
      if (mounted) {
        setState(() {
          _draft = saved;
          _dirty = false;
          _saveRequest = null;
          _publishOperation = null;
          _message = 'Draft saved on the office computer.';
        });
      }
    } catch (failure) {
      _failed(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    _publishOperation ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final publication = await widget.store.publishProcedureDraft(
        draftId: _draft!['id'] as String,
        expectedRevision: _draft!['revision'] as int,
        operationId: _publishOperation!,
      );
      if (mounted) {
        setState(() {
          _dirty = false;
          _busy = false;
        });
        Navigator.pop(context, publication);
      }
    } catch (failure) {
      _failed(failure);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _failed(Object failure) {
    if (!mounted) return;
    final message = _failureMessage(failure);
    final lower = message.toLowerCase();
    setState(() {
      _stale =
          lower.contains('stale') ||
          lower.contains('revision') ||
          lower.contains('reload') ||
          lower.contains('already published') ||
          lower.contains('was published');
      _error = _stale
          ? '$message Your changes are still visible here. Reload the saved '
                'draft before saving or publishing again.'
          : '$message Your changes are still visible. Retry with the same '
                'inputs, or edit them before trying again.';
    });
  }

  bool get _readyToPublish =>
      _draft != null &&
      !_busy &&
      !_dirty &&
      !_stale &&
      !_finalized &&
      _title.text.trim().isNotEmpty &&
      _steps.isNotEmpty &&
      _steps.every((step) => step.label.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit checklist copy')),
        body: page([
          notice('Checklist copies can only be edited on the office computer.'),
        ]),
      );
    }
    final draft = _draft;
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _finalized ? 'Saved checklist copy' : 'Edit checklist copy',
          ),
        ),
        body: Form(
          key: _form,
          child: page([
            if (_error != null) notice(_error!, error: true),
            if (_message != null) notice(_message!),
            if (_busy) const LinearProgressIndicator(),
            if (draft != null) ...[
              Text(
                'Source: ${draft['source']['title']} · '
                'v${draft['source']['version']}',
              ),
              Text('Draft revision ${draft['revision']}'),
              const SizedBox(height: 12),
              const Text(
                'This is an independent copy. Publishing creates a '
                'separate checklist at v1. The source and prepared '
                'inspections keep their original instructions.',
              ),
              if (_finalized)
                notice(
                  'This copy has been published and is read-only. '
                  'Open its published checklist from the library to prepare '
                  'an inspection or make another copy.',
                ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('procedure-title'),
                controller: _title,
                enabled: _editable,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Checklist title'),
                onChanged: (_) => _changed(),
              ),
              for (final (index, step) in _steps.indexed) _step(step, index),
              if (!_finalized) ...[
                OutlinedButton.icon(
                  key: const Key('procedure-add-step'),
                  onPressed: !_editable || _steps.length >= 200
                      ? null
                      : () {
                          _steps.add(
                            _StepEditor({
                              'id': const Uuid().v4(),
                              'label': '',
                              'input_type': 'check',
                              'required': true,
                              'allow_na': false,
                            }),
                          );
                          _changed();
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add step'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('procedure-save'),
                  onPressed: _busy || _stale ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save draft'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('procedure-publish'),
                  onPressed: _readyToPublish ? _publish : null,
                  child: const Text('Publish checklist'),
                ),
                if (_dirty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Save your changes before publishing.'),
                  ),
                if (!_dirty &&
                    (_steps.isEmpty ||
                        _title.text.trim().isEmpty ||
                        _steps.any((step) => step.label.text.trim().isEmpty)))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Drafts can be unfinished. To publish, enter a '
                      'title and at least one described step.',
                    ),
                  ),
                TextButton(
                  key: const Key('procedure-reload'),
                  onPressed: _busy ? null : _reload,
                  child: const Text('Reload saved draft'),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _step(_StepEditor step, int index) => Card(
    key: ValueKey(step.id),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step ${index + 1}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!_finalized)
            Wrap(
              children: [
                IconButton(
                  key: ValueKey('procedure-step-up-$index'),
                  tooltip: 'Move step ${index + 1} up',
                  onPressed: !_editable || index == 0
                      ? null
                      : () {
                          _steps.removeAt(index);
                          _steps.insert(index - 1, step);
                          _changed();
                        },
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('procedure-step-down-$index'),
                  tooltip: 'Move step ${index + 1} down',
                  onPressed: !_editable || index == _steps.length - 1
                      ? null
                      : () {
                          _steps.removeAt(index);
                          _steps.insert(index + 1, step);
                          _changed();
                        },
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  key: ValueKey('procedure-step-remove-$index'),
                  tooltip: 'Remove step ${index + 1}',
                  onPressed: !_editable
                      ? null
                      : () {
                          _steps.remove(step);
                          _retired.add(step);
                          _changed();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          TextFormField(
            key: ValueKey('procedure-step-label-$index'),
            controller: step.label,
            enabled: _editable,
            maxLength: 1000,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Inspection step'),
            onChanged: (_) => _changed(),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: ValueKey('procedure-step-type-$index'),
            child: DropdownButtonFormField<String>(
              key: ValueKey('${step.id}-${step.type}'),
              initialValue: step.type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Response'),
              items: const [
                DropdownMenuItem(value: 'check', child: Text('Check result')),
                DropdownMenuItem(
                  value: 'number',
                  child: Text('Numeric reading'),
                ),
                DropdownMenuItem(
                  value: 'text',
                  child: Text('Written response'),
                ),
              ],
              onChanged: !_editable
                  ? null
                  : (type) {
                      step.type = type!;
                      _changed();
                    },
            ),
          ),
          if (step.type == 'number') ...[
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('procedure-step-unit-$index'),
              controller: step.unit,
              enabled: _editable,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Reading unit'),
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('procedure-step-min-$index'),
              controller: step.minimum,
              enabled: _editable,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Minimum (optional)',
              ),
              validator: _StepEditor.validNumber,
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('procedure-step-max-$index'),
              controller: step.maximum,
              enabled: _editable,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Maximum (optional)',
              ),
              validator: (value) {
                final problem = _StepEditor.validNumber(value);
                if (problem != null) return problem;
                final minimum = _StepEditor.number(step.minimum.text);
                final maximum = _StepEditor.number(value ?? '');
                return minimum != null && maximum != null && minimum > maximum
                    ? 'Maximum must be at least the minimum.'
                    : null;
              },
              onChanged: (_) => _changed(),
            ),
          ],
          SwitchListTile(
            key: ValueKey('procedure-step-required-$index'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Required response'),
            value: step.required,
            onChanged: !_editable
                ? null
                : (value) {
                    step.required = value;
                    _changed();
                  },
          ),
          SwitchListTile(
            key: ValueKey('procedure-step-na-$index'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow not applicable'),
            value: step.allowNa,
            onChanged: !_editable
                ? null
                : (value) {
                    step.allowNa = value;
                    _changed();
                  },
          ),
        ],
      ),
    ),
  );
}

class _SaveRequest {
  _SaveRequest({
    required this.id,
    required this.revision,
    required this.title,
    required List<Json> items,
  }) : items = (jsonDecode(canonical(items)) as List)
           .map((item) => Map<String, dynamic>.from(item as Map))
           .toList();

  final String id, title;
  final int revision;
  final List<Json> items;
}

class _StepEditor {
  _StepEditor(Json definition)
    : original = jsonDecode(canonical(definition)) as Json,
      id = definition['id'] as String,
      type = definition['input_type'] as String,
      required = definition['required'] != false,
      allowNa = definition['allow_na'] == true {
    label.text = definition['label'] as String;
    unit.text = definition['unit']?.toString() ?? '';
    minimum.text = definition['min']?.toString() ?? '';
    maximum.text = definition['max']?.toString() ?? '';
  }

  final Json original;
  final String id;
  final label = TextEditingController(), unit = TextEditingController();
  final minimum = TextEditingController(), maximum = TextEditingController();
  String type;
  bool required, allowNa;

  static num? number(String value) =>
      num.tryParse(value.trim().replaceAll(',', '.'));

  static String? validNumber(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = number(value!);
    return parsed == null || !parsed.isFinite || parsed.abs() > 1e12
        ? 'Enter a finite reading within the supported range.'
        : null;
  }

  Json value() {
    final item = {
      ...original,
      'id': id,
      'label': label.text.trim(),
      'input_type': type,
      'required': required,
      'allow_na': allowNa,
    };
    if (type != original['input_type']) {
      item.remove('unit');
      item.remove('min');
      item.remove('max');
      if (type == 'number') {
        item['unit'] = unit.text.trim();
        if (minimum.text.trim().isNotEmpty) {
          item['min'] = number(minimum.text);
        }
        if (maximum.text.trim().isNotEmpty) {
          item['max'] = number(maximum.text);
        }
      }
    } else if (type == 'number') {
      // An untouched field retains its exact source shape: absent, null,
      // explicit empty unit and zero are separate recorded values.
      if (unit.text != (original['unit']?.toString() ?? '')) {
        item['unit'] = unit.text.trim();
      }
      if (minimum.text != (original['min']?.toString() ?? '')) {
        item['min'] = number(minimum.text);
      }
      if (maximum.text != (original['max']?.toString() ?? '')) {
        item['max'] = number(maximum.text);
      }
    }
    return item;
  }

  void dispose() {
    label.dispose();
    unit.dispose();
    minimum.dispose();
    maximum.dispose();
  }
}

String _failureMessage(Object failure) =>
    failure.toString().replaceFirst('Bad state: ', '');
