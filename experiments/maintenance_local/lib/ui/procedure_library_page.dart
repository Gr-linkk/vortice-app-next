import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../lab_store.dart';
import '../model.dart';
import '../procedure_library_store.dart';
import 'common.dart';
import 'procedure_editor_page.dart';
import 'procedure_publication_page.dart';

/// Office entry for immutable publications and independently saved copies.
class ProcedureLibraryPage extends StatefulWidget {
  const ProcedureLibraryPage({super.key, required this.store});

  final LabStore store;

  @override
  State<ProcedureLibraryPage> createState() => _ProcedureLibraryPageState();
}

class _ProcedureLibraryPageState extends State<ProcedureLibraryPage> {
  final _copyOperations = <String, String>{};
  List<Json> _drafts = [];
  String? _error;
  bool _busy = false, _readable = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    if (!widget.store.office) return;
    try {
      _drafts = widget.store.procedureDrafts;
      _readable = true;
      _error = null;
    } catch (failure) {
      _readable = false;
      _drafts = [];
      _error = _message(failure);
    }
  }

  Future<void> _editor(Json draft) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcedureEditorPage(store: widget.store, draft: draft),
      ),
    );
    if (!mounted) return;
    setState(_read);
    if (result is Map<String, dynamic>) await _preview(result);
  }

  Future<void> _preview(Json publication) async {
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcedurePublicationPage(
          store: widget.store,
          publication: publication,
        ),
      ),
    );
    if (mounted) setState(_read);
  }

  Future<void> _copy(Json publication) async {
    final id = publication['id'] as String;
    final operation = _copyOperations.putIfAbsent(id, () => const Uuid().v4());
    setState(() {
      _busy = true;
      _error = null;
    });
    Json? draft;
    try {
      draft = await widget.store.copyProcedureDraft(id, operationId: operation);
      _copyOperations.remove(id);
    } catch (failure) {
      if (mounted) setState(() => _error = _message(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (draft != null && mounted) await _editor(draft);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.office) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checklist library')),
        body: page([
          notice(
            'Open the checklist library on the office computer. '
            'Prepared inspections on this phone keep their published checklist.',
          ),
        ]),
      );
    }
    final publications = widget.store.templates;
    return Scaffold(
      appBar: AppBar(title: const Text('Checklist library')),
      body: page([
        const Text(
          'Preview a published checklist, prepare an inspection, or '
          'make an independent copy for future work.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Saved copies stay on the office computer until published. '
          'Existing inspections keep their original instructions.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          notice(_error!, error: true),
          TextButton(
            key: const Key('procedure-library-reload'),
            onPressed: _busy ? null : () => setState(_read),
            child: const Text('Reload library'),
          ),
        ],
        const SizedBox(height: 20),
        Text('Saved copies', style: Theme.of(context).textTheme.titleLarge),
        if (_readable && _drafts.isEmpty)
          notice('Make a copy of a published checklist to start a draft.'),
        for (final draft in _drafts)
          Card(
            key: ValueKey('procedure-draft-${draft['id']}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    (draft['title'] as String).trim().isEmpty
                        ? 'Untitled checklist copy'
                        : draft['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Draft revision ${draft['revision']} · '
                    '${draft['publishedTemplateId'] == null ? 'Not published' : 'Published as a separate checklist'}',
                  ),
                  Text(
                    'Source: ${draft['source']['title']} · '
                    'v${draft['source']['version']}',
                  ),
                  TextButton(
                    key: ValueKey('procedure-open-${draft['id']}'),
                    onPressed: _busy ? null : () => _editor(draft),
                    child: Text(
                      draft['publishedTemplateId'] == null
                          ? 'Open draft'
                          : 'View saved copy',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Published checklists',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (publications.isEmpty)
          notice('Author and publish your first checklist from preparation.'),
        for (final publication in publications)
          Card(
            key: ValueKey('procedure-publication-${publication['id']}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    publication['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Published v${publication['version']} · '
                    '${(publication['items'] as List).length} steps',
                  ),
                  Text(_provenance(publication)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        key: ValueKey('procedure-preview-${publication['id']}'),
                        onPressed: _busy ? null : () => _preview(publication),
                        child: const Text('Preview checklist'),
                      ),
                      TextButton(
                        key: ValueKey('procedure-copy-${publication['id']}'),
                        onPressed: _busy || !_readable
                            ? null
                            : () => _copy(publication),
                        child: const Text('Make a copy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

String _message(Object failure) =>
    failure.toString().replaceFirst('Bad state: ', '');

String _provenance(Json publication) {
  final provenance = jsonDecode(canonical(publication['provenance'])) as Json;
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
