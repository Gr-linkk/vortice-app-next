import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

const checklistEquipmentStates = <String, (String, String)>{
  '': ('Any state', 'Cualquier estado'),
  'walk_around': ('Walk around', 'Inspección exterior'),
  'stopped': ('Stopped', 'Detenido'),
  'before_start': ('Before start', 'Antes de arrancar'),
  'start_up': ('Starting', 'Arranque'),
  'running': ('Running', 'En marcha'),
  'shutdown': ('Shutdown', 'Apagado'),
  'isolated': ('Isolated / locked out', 'Aislado / bloqueado'),
  'maintenance': ('Maintenance', 'Mantenimiento'),
  'restart': ('Restart', 'Reinicio'),
  'verification': ('Verification', 'Verificación'),
};

class ChecklistProcedureSource {
  const ChecklistProcedureSource(this.document, this.page, this.section);
  final String document, section;
  final int page;
  static ChecklistProcedureSource? fromDefinition(Map definition) {
    final source = definition['procedure_source'];
    final data = source is Map ? source : definition;
    final doc = data[source is Map ? 'document_id' : 'source_document_id'];
    final page = data[source is Map ? 'page' : 'source_page'];
    if (doc is! String ||
        doc.isEmpty ||
        page is! num ||
        page != page.toInt() ||
        page < 1 ||
        page > 30) {
      return null;
    }
    return ChecklistProcedureSource(
      doc,
      page.toInt(),
      data['section']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'document_id': document,
    'page': page,
    'section': section,
  };
}

final checklistSourceRepositoryProvider = Provider<ChecklistSourceRepository>((
  ref,
) {
  return ChecklistSourceRepository(ref.watch(sessionProvider)?.user.id ?? '');
});

class ChecklistSourceRepository {
  ChecklistSourceRepository(this.account);
  final String account;
  Future<Map<String, dynamic>> page(Map<String, dynamic> item) async {
    final source = ChecklistProcedureSource.fromDefinition(
      item['definition'] as Map? ?? {},
    );
    if (source == null) throw StateError('This step has no procedure page');
    final cache = AccountJsonCache(
      account,
      () => supabase.auth.currentUser?.id,
    );
    final value = await cache.readThrough(
      'checklist_source:${item['template_id']}:${item['id']}:${source.document}:${source.page}',
      () async {
        cache.checkAccount();
        final raw = await supabase
            .rpc(
              'checklist_source_page',
              params: {
                'p_template': item['template_id'],
                'p_item': item['id'],
                'p_document': source.document,
                'p_page': source.page,
              },
            )
            .timeout(const Duration(seconds: 8));
        cache.checkAccount();
        final row = Map<String, dynamic>.from(raw as Map);
        final bytes = await supabase.storage
            .from('maintenance-documents')
            .download(row['object_path'] as String)
            .timeout(const Duration(seconds: 12));
        cache.checkAccount();
        return {...row, 'bytes': base64Encode(bytes)};
      },
    );
    return Map<String, dynamic>.from(value as Map);
  }

  /// Loads all linked pages, including steps not yet scrolled into view.
  /// The readiness caller may surface a failure; a page tap always retries.
  Future<void> prefetch(Iterable<Map<String, dynamic>> items) async {
    final seen = <String>{};
    for (final item in items) {
      final source = ChecklistProcedureSource.fromDefinition(
        item['definition'] as Map? ?? {},
      );
      if (source != null &&
          seen.add(
            '${item['template_id']}:${item['id']}:${source.document}:${source.page}',
          )) {
        await page(item);
      }
    }
  }
}

class ChecklistProcedureLink extends ConsumerWidget {
  const ChecklistProcedureLink({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ChecklistProcedureSource.fromDefinition(
      item['definition'] as Map? ?? {},
    );
    if (source == null) return const SizedBox.shrink();
    final es = isSpanish(context);
    return TextButton.icon(
      icon: const Icon(Icons.menu_book_outlined),
      label: Text(
        '${es ? 'Ver procedimiento' : 'View procedure'} · ${source.section.isEmpty ? '${es ? 'Página guardada' : 'Saved page'} ${source.page}' : source.section}',
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChecklistProcedurePage(item: item),
        ),
      ),
    );
  }
}

class ChecklistProcedurePage extends ConsumerStatefulWidget {
  const ChecklistProcedurePage({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  ConsumerState<ChecklistProcedurePage> createState() =>
      _ChecklistProcedurePageState();
}

class _ChecklistProcedurePageState
    extends ConsumerState<ChecklistProcedurePage> {
  Future<Map<String, dynamic>>? _page;
  ChecklistSourceRepository? _repository;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(checklistSourceRepositoryProvider);
    if (!identical(repository, _repository)) {
      _repository = repository;
      _page = repository.page(widget.item);
    }
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Procedimiento' : 'Procedure')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _page,
        builder: (context, state) {
          if (state.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      es
                          ? 'No se pudo abrir la página. Conéctate y comprueba tu acceso.'
                          : 'This page could not be opened. Connect and check your access.',
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _page = repository.page(widget.item)),
                      child: Text(es ? 'Reintentar' : 'Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final row = state.data!;
          final Uint8List bytes = base64Decode(row['bytes'] as String);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${row['title']} · ${es ? 'Página guardada' : 'Saved page'} ${row['page']}',
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 6,
                  child: Center(child: Image.memory(bytes)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
