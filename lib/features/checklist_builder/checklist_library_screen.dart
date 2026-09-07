import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'checklist_builder_repository.dart';
import 'checklist_editor_screen.dart';
import 'checklist_preview_screen.dart';
import 'checklist_use_screen.dart';

class ChecklistLibraryScreen extends ConsumerStatefulWidget {
  const ChecklistLibraryScreen({super.key});
  @override
  ConsumerState<ChecklistLibraryScreen> createState() =>
      _ChecklistLibraryScreenState();
}

class _ChecklistLibraryScreenState
    extends ConsumerState<ChecklistLibraryScreen> {
  final _search = TextEditingController();
  String _kind = 'all';
  bool _published = false;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _editor(
    Map<String, dynamic> catalog, {
    Map<String, dynamic>? procedure,
    Map<String, dynamic> initial = const {},
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChecklistEditorScreen(
          catalog: catalog,
          procedure: procedure,
          initial: initial,
        ),
      ),
    );
    ref.invalidate(checklistLibraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final state = ref.watch(checklistLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Listas de revisión' : 'Checklist library'),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(friendlyError(context, error)),
                TextButton(
                  onPressed: () => ref.invalidate(checklistLibraryProvider),
                  child: Text(es ? 'Reintentar' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (catalog) {
          final canAuthor =
              catalog['can_pm'] == true || catalog['can_preop'] == true;
          final query = _search.text.trim().toLowerCase();
          final source = _published || !canAuthor
              ? checklistRows(catalog['templates'])
              : checklistRows(catalog['procedures']);
          final rows = source.where((row) {
            final data = row['draft'] as Map? ?? row;
            return (_kind == 'all' || data['checklist_type'] == _kind) &&
                '${data['name']} ${data['description'] ?? ''}'
                    .toLowerCase()
                    .contains(query);
          }).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(checklistLibraryProvider);
              await ref.read(checklistLibraryProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  es
                      ? 'Crea procedimientos de mantenimiento y revisiones antes de operar.'
                      : 'Build maintenance procedures and checks to complete before operating equipment.',
                ),
                const SizedBox(height: 12),
                if (canAuthor)
                  FilledButton.icon(
                    onPressed: () => _editor(catalog),
                    icon: const Icon(Icons.add),
                    label: Text(es ? 'Crear lista' : 'Create checklist'),
                  ),
                if (!canAuthor)
                  Text(
                    es
                        ? 'Tu acceso permite consultar las listas publicadas. La creación requiere permisos de responsable y la función habilitada.'
                        : 'You can view published checklists. Creating them requires manager access and the relevant capability.',
                  ),
                const SizedBox(height: 12),
                if (canAuthor)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(es ? 'Mis listas' : 'My checklists'),
                        selected: !_published,
                        onSelected: (_) => setState(() => _published = false),
                      ),
                      ChoiceChip(
                        label: Text(
                          es ? 'Biblioteca publicada' : 'Published library',
                        ),
                        selected: _published,
                        onSelected: (_) => setState(() => _published = true),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: es ? 'Buscar listas' : 'Search checklists',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in [
                      ('all', es ? 'Todas' : 'All'),
                      ('pm', es ? 'Mantenimiento' : 'PM'),
                      (
                        'operator_daily',
                        es ? 'Antes de operar' : 'Pre-operation',
                      ),
                    ])
                      ChoiceChip(
                        label: Text(kind.$2),
                        selected: _kind == kind.$1,
                        onSelected: (_) => setState(() => _kind = kind.$1),
                      ),
                  ],
                ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      es
                          ? 'No hay listas aquí. Crea una o copia una de la biblioteca publicada.'
                          : 'No checklists here. Create one or copy a published starter.',
                    ),
                  ),
                for (final row in rows)
                  Builder(
                    builder: (context) {
                      final data = Map<String, dynamic>.from(
                        row['draft'] as Map? ?? row,
                      );
                      final isProcedure = row.containsKey('draft'),
                          archived = row['archived'] == true;
                      final isPM = data['checklist_type'] == 'pm';
                      final published = isProcedure
                          ? checklistRows(catalog['templates'])
                                .where(
                                  (t) =>
                                      t['id'] == row['published_template_id'],
                                )
                                .firstOrNull
                          : row;
                      final canCopy = isPM
                          ? catalog['can_pm'] == true
                          : catalog['can_preop'] == true;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['name'] as String? ?? '',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '${isPM ? (es ? 'Mantenimiento preventivo' : 'Preventive maintenance') : (es ? 'Antes de operar' : 'Pre-operation')} · ${archived
                                    ? (es ? 'Archivada' : 'Archived')
                                    : published == null
                                    ? (es ? 'Borrador' : 'Draft')
                                    : '${es ? 'Publicada v' : 'Published v'}${published['version']}'}',
                              ),
                              if (!isProcedure)
                                Text(
                                  row['client_id'] == null
                                      ? (es
                                            ? 'Plantilla compartida'
                                            : 'Shared starter')
                                      : (es
                                            ? 'Biblioteca de empresa'
                                            : 'Company library'),
                                ),
                              if (isProcedure &&
                                  published != null &&
                                  (row['revision'] as num? ?? 0) >
                                      (row['published_revision'] as num? ?? 0))
                                Text(
                                  es
                                      ? 'Hay cambios de borrador sin publicar.'
                                      : 'Draft changes have not been published.',
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ChecklistPreviewScreen(draft: data),
                                      ),
                                    ),
                                    child: Text(
                                      es ? 'Vista previa' : 'Preview',
                                    ),
                                  ),
                                  if (isProcedure && !archived)
                                    TextButton(
                                      onPressed: () =>
                                          _editor(catalog, procedure: row),
                                      child: Text(
                                        es ? 'Editar borrador' : 'Edit draft',
                                      ),
                                    ),
                                  if (published != null && !archived)
                                    TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChecklistUseScreen(
                                            template: published,
                                            catalog: catalog,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        es ? 'Usar lista' : 'Use checklist',
                                      ),
                                    ),
                                  if (canCopy)
                                    TextButton(
                                      onPressed: () => _editor(
                                        catalog,
                                        initial: isProcedure
                                            ? {
                                                ...data,
                                                'name':
                                                    '${data['name']} (copy)',
                                                'source_template_id':
                                                    row['published_template_id'],
                                              }
                                            : copiedChecklistDraft(row),
                                      ),
                                      child: Text(
                                        es ? 'Crear copia' : 'Make a copy',
                                      ),
                                    ),
                                  if (isProcedure && !archived)
                                    TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              _ArchiveChecklistScreen(
                                                procedure: row,
                                              ),
                                        ),
                                      ),
                                      child: Text(es ? 'Archivar' : 'Archive'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ArchiveChecklistScreen extends ConsumerStatefulWidget {
  const _ArchiveChecklistScreen({required this.procedure});
  final Map<String, dynamic> procedure;
  @override
  ConsumerState<_ArchiveChecklistScreen> createState() =>
      _ArchiveChecklistScreenState();
}

class _ArchiveChecklistScreenState
    extends ConsumerState<_ArchiveChecklistScreen> {
  final _operation = const Uuid().v4();
  bool _busy = false;
  Object? _error;
  Future<void> _archive() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(checklistBuilderRepositoryProvider)
          .save(
            _operation,
            widget.procedure['id'] as String,
            (widget.procedure['revision'] as num).toInt(),
            'archive',
            {},
          );
      ref.invalidate(checklistLibraryProvider);
      ref.invalidate(checklistTemplatesProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Archivar lista' : 'Archive checklist')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            (widget.procedure['draft'] as Map)['name'] as String,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            es
                ? 'No estará disponible para trabajos nuevos. Los trabajos iniciados y el historial conservan su versión.'
                : 'It will no longer be available for new work. Started work and history keep their original version.',
          ),
          if (_error != null) Text(friendlyError(context, _error!)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _archive,
            child: Text(es ? 'Archivar lista' : 'Archive checklist'),
          ),
        ],
      ),
    );
  }
}
