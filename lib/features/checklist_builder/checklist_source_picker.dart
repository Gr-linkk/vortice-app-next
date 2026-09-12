import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/agent_access/maintenance_documents_repository.dart';
import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';

class ChecklistSourcePicker extends ConsumerStatefulWidget {
  const ChecklistSourcePicker({super.key, required this.clientId});
  final String clientId;
  @override
  ConsumerState<ChecklistSourcePicker> createState() =>
      _ChecklistSourcePickerState();
}

class _ChecklistSourcePickerState extends ConsumerState<ChecklistSourcePicker> {
  Future<List<Map<String, dynamic>>>? _documents;
  MaintenanceDocumentsRepository? _repository;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(maintenanceDocumentsRepositoryProvider);
    if (!identical(repository, _repository)) {
      _repository = repository;
      _documents = repository.list(widget.clientId);
    }
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Elegir procedimiento' : 'Choose procedure'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _documents,
        builder: (context, state) {
          if (state.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(
                  () => _documents = repository.list(widget.clientId),
                ),
                child: Text(es ? 'Reintentar' : 'Retry loading documents'),
              ),
            );
          }
          if (!state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                es
                    ? 'La página elegida estará disponible para las personas autorizadas a ejecutar esta lista. Añade documentos en la biblioteca de manuales.'
                    : 'The chosen page will be available to people authorized to run this checklist. Add documents in the manual library.',
              ),
              if (state.data!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    es
                        ? 'No hay documentos guardados.'
                        : 'No saved documents yet.',
                  ),
                ),
              for (final document in state.data!)
                ExpansionTile(
                  title: Text(document['title'] as String),
                  children: [
                    for (final page
                        in (document['maintenance_document_pages'] as List? ??
                            []))
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          '${es ? 'Página guardada' : 'Saved page'} ${page['page']}',
                        ),
                        onTap: () => Navigator.pop(
                          context,
                          ChecklistProcedureSource(
                            document['id'] as String,
                            (page['page'] as num).toInt(),
                            '',
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
