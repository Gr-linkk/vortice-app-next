import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'maintenance_document_importer.dart';
import 'maintenance_documents_repository.dart';
import 'agent_plan_review_screen.dart';

class MaintenanceDocumentsScreen extends ConsumerWidget {
  const MaintenanceDocumentsScreen({
    super.key,
    required this.fleet,
    required this.fleetName,
  });
  final String fleet, fleetName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(sessionProvider)?.user.id;
    final profile = ref.watch(authStatusProvider).profile;
    if (actor == null ||
        profile?.id != actor ||
        ![
          UserRole.owner,
          UserRole.client,
          UserRole.clientAdmin,
        ].contains(profile?.role)) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    return MaintenanceDocumentsPanel(
      key: ValueKey(actor),
      repository: ref.watch(maintenanceDocumentsRepositoryProvider),
      fleet: fleet,
      fleetName: fleetName,
      importer: MaintenanceDocumentImporter(),
    );
  }
}

class MaintenanceDocumentsPanel extends StatefulWidget {
  const MaintenanceDocumentsPanel({
    super.key,
    required this.repository,
    required this.fleet,
    required this.fleetName,
    required this.importer,
  });
  final MaintenanceDocumentsRepository repository;
  final String fleet, fleetName;
  final MaintenanceDocumentImporter importer;
  @override
  State<MaintenanceDocumentsPanel> createState() =>
      _MaintenanceDocumentsPanelState();
}

class _MaintenanceDocumentsPanelState extends State<MaintenanceDocumentsPanel> {
  final _title = TextEditingController();
  final _scroll = ScrollController();
  String _id = const Uuid().v4();
  List<MaintenanceDocumentPage> _pages = [];
  List<Map<String, dynamic>> _documents = [];
  bool _busy = false, _locked = false, _saved = false;
  String? _message;
  String t(String en, String es) => isSpanish(context) ? es : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _scroll.dispose();
    _pages = [];
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final docs = await widget.repository.list(widget.fleet);
      if (mounted) setState(() => _documents = docs);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            'Could not load documents. Retry while online.',
            'No se pudieron cargar los documentos. Reintenta con conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(
    Future<List<MaintenanceDocumentPage>> Function() pick,
  ) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final pages = await pick();
      if (!mounted) return;
      if (_pages.length + pages.length > 30 ||
          [..._pages, ...pages].fold<int>(0, (n, p) => n + p.bytes.length) >
              40 * 1024 * 1024) {
        throw const FormatException('Too many pages');
      }
      setState(() => _pages = [..._pages, ...pages]);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            'Could not import. Use clear JPEG/PNG pages under 5 MB each, or a PDF under 20 MB and 30 pages. Check camera/file permission. Split large manuals into sections.',
            'No se pudo importar. Usa páginas JPEG/PNG claras de menos de 5 MB, o un PDF de menos de 20 MB y 30 páginas. Revisa los permisos. Divide los manuales grandes.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _locked = true;
      _message = null;
    });
    try {
      await widget.repository.save(
        _id,
        widget.fleet,
        _title.text.trim(),
        List.unmodifiable(_pages),
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _pages = [];
        _message = t(
          'Saved. Ask your connected agent to combine this manual with equipment hours and service history, then draft plans and checklists for your review.',
          'Guardado. Pide al agente conectado que combine este manual con las horas y el historial del equipo para preparar planes y listas que puedas revisar.',
        );
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            'Upload could not be confirmed. Keep this screen open and retry; the same pages and document ID will be reused.',
            'No se pudo confirmar la carga. Mantén esta pantalla abierta y reintenta; se usarán las mismas páginas y el mismo identificador.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedFormGuard(
    isDirty: () => _pages.isNotEmpty && !_saved,
    controllers: [_title],
    fallbackRoute: '/more',
    busy: _busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(t('Maintenance documents', 'Documentos de mantenimiento')),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.fleetName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Scan each page or import a PDF. Confirm the page order and legibility before saving. Only connections with document permission can read these pages.',
              'Escanea cada página o importa un PDF. Confirma el orden y la legibilidad antes de guardar. Solo las conexiones con permiso de documentos pueden leerlas.',
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!, semanticsLabel: _message),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_saved)
            FilledButton(
              onPressed: () => setState(() {
                _id = const Uuid().v4();
                _saved = false;
                _locked = false;
                _title.clear();
                _message = null;
              }),
              child: Text(
                t('Scan another document', 'Escanear otro documento'),
              ),
            ),
          if (!_saved) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              enabled: !_busy && !_locked,
              maxLength: 160,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t(
                  'Document title and revision',
                  'Título y revisión del documento',
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy || _locked
                      ? null
                      : () => _import(widget.importer.camera),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(t('Scan page', 'Escanear página')),
                ),
                OutlinedButton(
                  onPressed: _busy || _locked
                      ? null
                      : () => _import(widget.importer.photos),
                  child: Text(t('Photos', 'Fotos')),
                ),
                OutlinedButton(
                  onPressed: _busy || _locked
                      ? null
                      : () => _import(widget.importer.pdf),
                  child: const Text('PDF'),
                ),
              ],
            ),
            if (!_locked)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _import(widget.importer.recover),
                child: Text(
                  t(
                    'Recover interrupted camera capture',
                    'Recuperar captura interrumpida',
                  ),
                ),
              ),
            for (var i = 0; i < _pages.length; i++)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text('${t('Page', 'Página')} ${i + 1}'),
                      trailing: !_locked
                          ? IconButton(
                              tooltip: t('Remove page', 'Quitar página'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _pages.removeAt(i)),
                              icon: const Icon(Icons.close),
                            )
                          : null,
                    ),
                    SizedBox(
                      height: 200,
                      child: InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog.fullscreen(
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: CloseButton(
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                                Expanded(
                                  child: InteractiveViewer(
                                    maxScale: 8,
                                    child: Image.memory(_pages[i].bytes),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: Image.memory(
                          _pages[i].bytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Saved documents', 'Documentos guardados'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _load,
                tooltip: t('Refresh', 'Actualizar'),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          for (final d in _documents)
            Card(
              child: ExpansionTile(
                title: Text(d['title'] as String),
                subtitle: Text(
                  '${(d['maintenance_document_pages'] as List).length} ${t('pages', 'páginas')}',
                ),
                children: [
                  SelectableText('ID: ${d['id']}'),
                  for (final proposal
                      in (d['agent_plan_drafts'] as List? ?? []))
                    ListTile(
                      title: Text(
                        proposal['draft']['interval_label'] as String,
                      ),
                      subtitle: Text(
                        proposal['applied_plan_id'] == null
                            ? t(
                                'Plan draft · review and edit',
                                'Borrador de plan · revisar y editar',
                              )
                            : t(
                                'Reviewed plan saved',
                                'Plan revisado y guardado',
                              ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AgentPlanReviewScreen(
                            id: proposal['id'] as String,
                          ),
                        ),
                      ),
                    ),
                  for (final p
                      in (d['maintenance_document_pages'] as List)..sort(
                        (a, b) =>
                            (a['page'] as int).compareTo(b['page'] as int),
                      ))
                    ListTile(
                      title: Text('${t('Page', 'Página')} ${p['page']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MaintenanceSourcePageScreen(
                            document: d['id'] as String,
                            page: p['page'] as int,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _saved ? null : SafeArea(child: Padding(padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: _busy || _pages.isEmpty || _title.text.trim().length<3 ? null : _save,
          child: Text(_locked ? t('Retry upload','Reintentar carga') : t('Save document','Guardar documento'))))),
    ),
  );
}

class MaintenanceSourcePageScreen extends ConsumerWidget {
  const MaintenanceSourcePageScreen({
    super.key,
    required this.document,
    required this.page,
  });
  final String document;
  final int page;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(maintenanceDocumentsRepositoryProvider);
    final actor = ref.watch(sessionProvider)?.user.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${isSpanish(context) ? 'Página fuente' : 'Source page'} $page',
        ),
      ),
      body: actor == null
          ? const SizedBox()
          : FutureBuilder(
              key: ValueKey('$actor/$document/$page'),
              future: repository.page(document, page),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      isSpanish(context)
                          ? 'Página no disponible. Reabre para reintentar.'
                          : 'Page unavailable. Reopen to retry.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: Image.memory(snapshot.data!),
                  ),
                );
              },
            ),
    );
  }
}
