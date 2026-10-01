import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../lab_store.dart';
import '../maintenance_domain.dart';
import '../model.dart';
import '../procedure_library_store.dart';
import 'common.dart';
import 'inspection_content.dart';
import 'procedure_editor_page.dart';

/// A detached immutable definition, never an inspection answer document.
class ProcedurePublicationPage extends StatefulWidget {
  const ProcedurePublicationPage({
    super.key,
    required this.store,
    required this.publication,
  });

  final LabStore store;
  final Json publication;

  @override
  State<ProcedurePublicationPage> createState() =>
      _ProcedurePublicationPageState();
}

class _ProcedurePublicationPageState extends State<ProcedurePublicationPage> {
  final _title = TextEditingController();
  final _form = GlobalKey<FormState>();
  Json? _publication, _prepared;
  String? _equipmentId, _error, _copyOperation;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    try {
      final source = jsonDecode(canonical(widget.publication)) as Json;
      validateCatalog({
        'version': 1,
        'companyId': 'procedure-preview-validation',
        'company': 'Procedure preview',
        'coordinatorName': 'Procedure preview',
        'equipment': <Json>[],
        'templates': [source],
        'jobs': <Json>[],
      });
      _publication = source;
      _title.text = source['title'] as String;
      if (widget.store.office) {
        _equipmentId = widget.store.equipment.firstOrNull?['id'] as String?;
      }
    } catch (failure) {
      _error = _message(failure);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    _copyOperation ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    Json? draft;
    try {
      draft = await widget.store.copyProcedureDraft(
        _publication!['id'] as String,
        operationId: _copyOperation!,
      );
      _copyOperation = null;
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || draft == null) return;
    final publication = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcedureEditorPage(store: widget.store, draft: draft!),
      ),
    );
    if (mounted && publication is Map<String, dynamic>) {
      await Navigator.pushReplacement<Object?, Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => ProcedurePublicationPage(
            store: widget.store,
            publication: publication,
          ),
        ),
      );
    }
  }

  Future<void> _prepare() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await widget.store.prepareWork(
        equipmentId: _equipmentId!,
        templateId: _publication!['id'] as String,
        title: _title.text.trim(),
      );
      if (mounted) setState(() => _prepared = job);
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final publication = _publication;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Preview checklist')),
        body: page([
          if (_error != null) notice(_error!, error: true),
          if (publication != null) ...[
            Text(
              publication['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              'Published v${publication['version']} · '
              '${(publication['items'] as List).length} steps',
            ),
            const SizedBox(height: 12),
            const Text(
              'This preview shows the published instructions. '
              'It does not record inspection answers.',
            ),
            const SizedBox(height: 12),
            Text(_provenance(publication)),
            if ((publication['provenance'] as Map)['kind'] == 'local-reference')
              ExpansionTile(
                key: const Key('procedure-source-reference'),
                title: const Text('Source reference'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      (publication['provenance'] as Map)['reference'] as String,
                    ),
                  ),
                ],
              ),
            for (final (index, item) in (publication['items'] as List).indexed)
              Card(
                key: ValueKey('procedure-preview-step-$index'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${index + 1}. ${item['label']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stepDefinition(Map<String, dynamic>.from(item as Map)),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.store.office) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('procedure-publication-copy'),
                onPressed: _busy ? null : _copy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Make a copy'),
              ),
              const Text(
                'A copy can be edited and published as a separate '
                'checklist. This publication and prepared inspections stay intact.',
              ),
              const SizedBox(height: 24),
              Text(
                'Prepare an inspection',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_prepared != null) ...[
                notice(
                  'Inspection prepared: ${_prepared!['title']}. '
                  'Open it from Inspections to record the work.',
                ),
                FilledButton(
                  key: const Key('procedure-prepared-done'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ] else if (widget.store.equipment.isEmpty)
                notice(
                  'Add equipment from preparation, then return to this '
                  'checklist to prepare an inspection.',
                )
              else
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'The new inspection keeps this exact checklist. '
                        'No answers are copied from earlier inspections.',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const Key('procedure-equipment'),
                        initialValue: _equipmentId,
                        isDense: false,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          labelText: 'Equipment',
                        ),
                        items: widget.store.equipment
                            .map(
                              (equipment) => DropdownMenuItem(
                                value: equipment['id'] as String,
                                child: Text(equipmentName(equipment)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (id) => setState(() => _equipmentId = id),
                        validator: (id) => id == null
                            ? 'Select equipment for this inspection.'
                            : null,
                      ),
                      if (_equipmentId != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Selected equipment: ${equipmentName(widget.store.equipment.where((equipment) => equipment['id'] == _equipmentId).firstOrNull)}',
                          key: const Key('procedure-selected-equipment'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('procedure-inspection-title'),
                        controller: _title,
                        enabled: !_busy,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Inspection title',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter an inspection title.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('procedure-prepare'),
                        onPressed: _busy ? null : _prepare,
                        child: Text(
                          _busy ? 'Preparing…' : 'Prepare inspection',
                        ),
                      ),
                    ],
                  ),
                ),
            ] else
              notice(
                'The office computer prepares inspections and authors '
                'checklists. This published preview is read-only.',
              ),
          ],
        ]),
      ),
    );
  }
}

String _message(Object failure) =>
    failure.toString().replaceFirst('Bad state: ', '');

String _provenance(Json publication) {
  final provenance = publication['provenance'] as Map;
  return switch (provenance['kind']) {
    'company-authored' => 'Company-authored',
    'manual-reference' => 'Manual reference: ${provenance['reference']}',
    _ => _localReferenceSummary(provenance['reference'] as String),
  };
}

String _localReferenceSummary(String reference) {
  final source = RegExp(
    r'^Independent copy of local publication [a-zA-Z0-9_-]{1,100}, version ([1-9][0-9]{0,6}), hash [a-f0-9]{64}\. Source title: (.+)$',
    dotAll: true,
  ).firstMatch(reference);
  if (source == null) return 'Local reference';
  return 'Independent copy · Source: ${source.group(2)} · v${source.group(1)}';
}
