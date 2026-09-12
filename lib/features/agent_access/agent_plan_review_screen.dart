import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_setup_screen.dart';
import 'agent_review_evidence.dart';

class AgentPlanRepository {
  AgentPlanRepository(this.client, this.actor);
  final SupabaseClient client;
  final String actor;
  Future<List<Map<String, dynamic>>> pending(String fleet, int page) => _guard(
    () => client
        .from('agent_plan_drafts')
        .select('id,draft,assets(name)')
        .eq('client_id', fleet)
        .isFilter('applied_plan_id', null)
        .order('created_at')
        .order('id')
        .range(page * 25, page * 25 + 25),
  );
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

  Future<Map<String, dynamic>> load(String id) async =>
      Map<String, dynamic>.from(
        await _guard(
              () => client.rpc(
                'agent_plan_review_context',
                params: {'p_draft': id},
              ),
            )
            as Map,
      );
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

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AgentReviewEvidence e,
  ) async {
    final actor = ref.read(sessionProvider)?.user.id;
    final repository = ref.read(agentPlanRepositoryProvider);
    final procedure = e.data['procedure'] as Map?;
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            if (ref.watch(sessionProvider)?.user.id != actor) {
              return const Scaffold(body: SizedBox());
            }
            return MaintenanceSetupScreen(
              kind: 'plan',
              assetId: e.proposal['asset_id'] as String,
              catalog: e.catalog,
              initial: {
                ...?e.plan,
                'interval_label': e.draft['interval_label'],
                'interval_hours': e.draft['interval_hours'],
                'meter_unit': e.unit,
                'engine_id': e.draft['engine_id'],
                'last_service_hours': e.baseline?.toString() ?? '',
                if (procedure?['published_template_id'] != null)
                  'checklist_template_id': procedure!['published_template_id'],
              },
              reviewContext: ExpansionTile(
                title: Text(
                  isSpanish(context)
                      ? 'Consultar fuente e historial'
                      : 'Refer to source and history',
                ),
                tilePadding: EdgeInsets.zero,
                children: [
                  AgentEquipmentEvidence(evidence: e),
                  AgentSourceEvidence(evidence: e),
                  AgentServiceEvidence(evidence: e),
                ],
              ),
              reviewedSave: (operation, data) =>
                  repository.apply(id, operation, data),
            );
          },
        ),
      ),
    );
    if (context.mounted) ref.invalidate(agentPlanReviewProvider(id));
  }

  Widget _action(BuildContext context, WidgetRef ref, AgentReviewEvidence e) {
    final es = isSpanish(context);
    if (e.applied) {
      return FilledButton.icon(
        onPressed: () =>
            context.push('/maintenance/assets/${e.proposal['asset_id']}'),
        icon: const Icon(Icons.task_alt),
        label: Text(es ? 'Ver plan guardado' : 'View saved plan'),
      );
    }
    if (!e.checklistReady) {
      return FilledButton.icon(
        onPressed: () async {
          ref.invalidate(checklistLibraryProvider);
          await context.push('/checklist-library');
          if (context.mounted) ref.invalidate(agentPlanReviewProvider(id));
        },
        icon: const Icon(Icons.checklist),
        label: Text(
          es
              ? 'Revisar y publicar la lista primero'
              : 'Review and publish the checklist first',
        ),
      );
    }
    return FilledButton.icon(
      onPressed: e.canEdit ? () => _edit(context, ref, e) : null,
      icon: const Icon(Icons.edit_outlined),
      label: Text(es ? 'Revisar y editar' : 'Review and edit'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final state = ref.watch(agentPlanReviewProvider(id));
    final value = state.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Revisar plan' : 'Plan review'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: state.isLoading
                ? null
                : () => ref.invalidate(agentPlanReviewProvider(id)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 16),
                Text(
                  es
                      ? 'No pudimos cargar la evidencia del plan.'
                      : 'We couldn’t load this plan’s evidence.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(agentPlanReviewProvider(id)),
                  child: Text(
                    es
                        ? 'No se pudo cargar. Reintentar.'
                        : 'Could not load. Retry.',
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final e = AgentReviewEvidence(data);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 840 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.6;
              final source = Column(
                children: [
                  AgentSourceEvidence(evidence: e),
                  AgentServiceEvidence(evidence: e),
                ],
              );
              final proposal = Column(
                children: [
                  AgentProposalSummary(evidence: e),
                  AgentEquipmentEvidence(evidence: e),
                ],
              );
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.catalog['asset']['name'] as String,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            e.draft['interval_label'] as String,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: Icon(
                                  e.applied
                                      ? Icons.check_circle_outline
                                      : Icons.rate_review_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  e.applied
                                      ? (es ? 'Plan guardado' : 'Plan saved')
                                      : (es ? 'Por revisar' : 'Review needed'),
                                ),
                              ),
                              if (!e.applied && e.baseline == null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    es
                                        ? 'Falta confirmar historial'
                                        : 'History needs confirmation',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!e.meterMatches)
                            Text(es ? 'La unidad del medidor cambió desde la propuesta. Verifica el manual y pide una propuesta nueva.' : 'The meter unit changed since this proposal. Verify the manual and ask for a new proposal.',
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          if (e.missingPlan ||
                              e.component.isEmpty ||
                              e.catalog['can_plan'] == false)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                es
                                    ? 'El equipo, plan o permiso de planificación ya no está disponible. Actualiza antes de continuar.'
                                    : 'The equipment, plan or planning permission is no longer available. Refresh before continuing.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: proposal),
                                const SizedBox(width: 20),
                                Expanded(child: source),
                              ],
                            )
                          else ...[
                            proposal,
                            source,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: value == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: _action(context, ref, AgentReviewEvidence(value)),
                ),
              ),
            ),
    );
  }
}
