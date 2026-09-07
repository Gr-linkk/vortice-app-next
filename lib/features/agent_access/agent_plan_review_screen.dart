import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_setup_screen.dart';
import 'maintenance_documents_screen.dart';

class AgentPlanRepository {
  AgentPlanRepository(this.client, this.actor);
  final SupabaseClient client;
  final String actor;
  Future<T> _guard<T>(Future<T> Function() request) async {
    if (client.auth.currentUser?.id != actor) {
      throw StateError('Account changed');
    }
    final answer = await request().timeout(const Duration(seconds: 20));
    if (client.auth.currentUser?.id != actor) {
      throw StateError('Account changed');
    }
    return answer;
  }

  Future<Map<String, dynamic>> load(String id) async {
    final proposal = await _guard(
      () => client.from('agent_plan_drafts').select().eq('id', id).single(),
    );
    final catalog = await _guard(
      () => client.rpc(
        'maintenance_asset_context',
        params: {'p_asset': proposal['asset_id']},
      ),
    );
    final checklist = proposal['draft']['checklist_procedure_id'] as String?;
    Map<String, dynamic>? procedure;
    if (checklist != null) {
      procedure = await _guard(
        () => client
            .from('checklist_procedures')
            .select('published_template_id,archived')
            .eq('id', checklist)
            .single(),
      );
    }
    return {'proposal': proposal, 'catalog': catalog, 'procedure': procedure};
  }

  Future<void> apply(
    String id,
    String operation,
    Map<String, dynamic> data,
  ) async {
    await _guard(
      () => client.rpc(
        'apply_agent_plan_draft',
        params: {'p_draft': id, 'p_operation': operation, 'p_data': data},
      ),
    );
  }
}

final agentPlanRepositoryProvider = Provider(
  (ref) =>
      AgentPlanRepository(supabase, ref.watch(sessionProvider)?.user.id ?? ''),
);
final agentPlanReviewProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(agentPlanRepositoryProvider).load(id),
    );

class AgentPlanReviewScreen extends ConsumerWidget {
  const AgentPlanReviewScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Revisar plan propuesto' : 'Review proposed plan'),
      ),
      body: ref
          .watch(agentPlanReviewProvider(id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(agentPlanReviewProvider(id)),
                child: Text(
                  es
                      ? 'No se pudo cargar. Reintentar.'
                      : 'Could not load. Retry.',
                ),
              ),
            ),
            data: (data) {
              final proposal = Map<String, dynamic>.from(
                data['proposal'] as Map,
              );
              final draft = Map<String, dynamic>.from(proposal['draft'] as Map);
              final catalog = Map<String, dynamic>.from(data['catalog'] as Map);
              final procedure = data['procedure'] as Map?;
              final component = (catalog['components'] as List)
                  .cast<Map>()
                  .where((e) => e['id'] == draft['engine_id'])
                  .firstOrNull;
              final existingPlan = (catalog['plans'] as List? ?? [])
                  .cast<Map>()
                  .where((p) => p['id'] == draft['existing_plan_id'])
                  .firstOrNull;
              final baseline = existingPlan?['last_service_hours'] as num?;
              final current = component?['current_hours'] as num?;
              final due = baseline == null
                  ? null
                  : baseline + (draft['interval_hours'] as num);
              final checklistReady =
                  !draft.containsKey('checklist_procedure_id') ||
                  (procedure?['published_template_id'] != null &&
                      procedure?['archived'] != true);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    draft['interval_label'] as String,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(catalog['asset']['name'] as String),
                  const SizedBox(height: 12),
                  Text(
                    '${es ? 'Intervalo propuesto' : 'Proposed interval'}: ${draft['interval_hours']} h',
                  ),
                  Text(
                    '${es ? 'Horas actuales registradas' : 'Recorded current hours'}: ${current == null ? (es ? 'Desconocidas' : 'Unknown') : '$current h'}',
                  ),
                  Text(
                    '${es ? 'Último servicio de esta tarea' : 'Last service for this task'}: ${baseline == null ? (es ? 'Por confirmar' : 'Needs confirmation') : '$baseline h'}',
                  ),
                  if (due != null)
                    Text(
                      '${es ? 'Próximo servicio propuesto' : 'Proposed next service'}: $due h${current == null ? '' : ' · ${due - current} h ${es ? 'restantes' : 'remaining'}'}',
                    ),
                  Text(
                    es
                        ? 'Verifica las páginas, advertencias y condiciones del manual. El plan automático solo programa por horas; las condiciones de calendario requieren seguimiento aparte.'
                        : 'Verify the manual pages, warnings and conditions. Automatic intervals use hours; calendar conditions require separate tracking.',
                  ),
                  if ((draft['notes'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(draft['notes'] as String),
                    ),
                  Text(
                    '${es ? 'Cita sin verificar' : 'Unverified source quote'}: ${draft['source_quote']}',
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MaintenanceSourcePageScreen(
                          document: proposal['document_id'] as String,
                          page: draft['source_page'] as int,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.description_outlined),
                    label: Text(
                      '${es ? 'Ver página' : 'View source page'} ${draft['source_page']}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!checklistReady)
                    TextButton(
                      onPressed: () {
                        ref.invalidate(checklistLibraryProvider);
                        context.push('/checklist-library');
                      },
                      child: Text(
                        es
                            ? 'Revisar y publicar la lista primero'
                            : 'Review and publish the checklist first',
                      ),
                    ),
                  if (proposal['applied_plan_id'] == null)
                    FilledButton(
                      onPressed:
                          !checklistReady ||
                              (draft['existing_plan_id'] != null &&
                                  existingPlan == null)
                          ? null
                          : () async {
                              final actor = ref.read(sessionProvider)?.user.id;
                              final repository = ref.read(
                                agentPlanRepositoryProvider,
                              );
                              await Navigator.push(
                                context,
                                MaterialPageRoute<bool>(
                                  builder: (_) => Consumer(
                                    builder: (context, ref, _) {
                                      if (ref.watch(sessionProvider)?.user.id !=
                                          actor) {
                                        return const Scaffold(body: SizedBox());
                                      }
                                      return MaintenanceSetupScreen(
                                        kind: 'plan',
                                        assetId: proposal['asset_id'] as String,
                                        catalog: catalog,
                                        initial: {
                                          ...?existingPlan,
                                          'interval_label':
                                              draft['interval_label'],
                                          'interval_hours':
                                              draft['interval_hours'],
                                          'engine_id': draft['engine_id'],
                                          'last_service_hours':
                                              baseline?.toString() ?? '',
                                          if (procedure?['published_template_id'] !=
                                              null)
                                            'checklist_template_id':
                                                procedure!['published_template_id'],
                                        },
                                        reviewedSave: (operation, data) =>
                                            repository.apply(
                                              id,
                                              operation,
                                              data,
                                            ),
                                      );
                                    },
                                  ),
                                ),
                              );
                              if (context.mounted) {
                                ref.invalidate(agentPlanReviewProvider(id));
                              }
                            },
                      child: Text(
                        es
                            ? 'Editar y guardar plan revisado'
                            : 'Edit and save reviewed plan',
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: () => context.push(
                        '/maintenance/assets/${proposal['asset_id']}',
                      ),
                      child: Text(es ? 'Ver plan guardado' : 'View saved plan'),
                    ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(agentPlanReviewProvider(id)),
                    child: Text(es ? 'Actualizar' : 'Refresh'),
                  ),
                ],
              );
            },
          ),
    );
  }
}
