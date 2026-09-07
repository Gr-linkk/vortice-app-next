import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';
import 'package:vortice_app/models/profile.dart';
import 'agent_access_repository.dart';
import 'agent_access_screen.dart';
import 'agent_pending_plans_screen.dart';
import 'agent_plan_review_screen.dart';
import 'agent_review_evidence.dart';
import 'maintenance_documents_screen.dart';

final agentWorkspaceProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(agentAccessRepositoryProvider).load(),
);

class AgentWorkspaceScreen extends ConsumerWidget {
  const AgentWorkspaceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authStatusProvider).profile;
    final session = ref.watch(sessionProvider);
    if (profile == null ||
        session?.user.id != profile.id ||
        ![
          UserRole.owner,
          UserRole.client,
          UserRole.clientAdmin,
        ].contains(profile.role)) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            isSpanish(context)
                ? 'Inicia sesión con una cuenta autorizada.'
                : 'Sign in with an authorized account.',
          ),
        ),
      );
    }
    return AgentWorkspacePanel(key: ValueKey(profile.id));
  }
}

class AgentWorkspacePanel extends ConsumerStatefulWidget {
  const AgentWorkspacePanel({super.key});
  @override
  ConsumerState<AgentWorkspacePanel> createState() => _AgentWorkspaceState();
}

class _AgentWorkspaceState extends ConsumerState<AgentWorkspacePanel> {
  String? fleet;
  Future<void> _connections() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AgentAccessScreen()),
    );
    if (mounted) ref.invalidate(agentWorkspaceProvider);
  }

  Future<void> _review(String id, String client) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => AgentPlanReviewScreen(id: id)),
    );
    if (mounted) {
      ref.invalidate(pendingAgentPlansProvider((client, 0)));
      ref.invalidate(agentWorkspaceProvider);
    }
  }

  String activity(Map<String, dynamic> event, bool es) {
    if (event['outcome'] == 'rejected') {
      return es ? 'Acción rechazada' : 'Action rejected';
    }
    if (event['outcome'] == 'replayed') {
      return es
          ? 'Reintento sin duplicados'
          : 'Retry without duplicate changes';
    }
    if (event['outcome'] == 'revoked') {
      return es ? 'Conexión revocada' : 'Connection revoked';
    }
    if (event['outcome'] == 'read') {
      return es ? 'Información consultada' : 'Information read';
    }
    return switch (event['action']) {
      'create_plan_draft' => es ? 'Plan propuesto' : 'Plan proposed',
      'create_checklist_draft' => es ? 'Lista propuesta' : 'Checklist proposed',
      'assign_work_order' => es ? 'Trabajo asignado' : 'Work assigned',
      'schedule_work_order' => es ? 'Trabajo programado' : 'Work scheduled',
      'edit_work_order' => es ? 'Alcance actualizado' : 'Work scope updated',
      'create_work_order_draft' => es ? 'Orden creada' : 'Work order created',
      _ => es ? 'Conexión creada' : 'Connection created',
    };
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final state = ref.watch(agentWorkspaceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Agentes' : 'Agents'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () {
              ref.invalidate(agentWorkspaceProvider);
              ref.invalidate(pendingAgentPlansProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: es ? 'Conexiones' : 'Connections',
            onPressed: _connections,
            icon: const Icon(Icons.tune),
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
                const SizedBox(height: 12),
                Text(
                  es
                      ? 'No pudimos cargar tu espacio de agentes.'
                      : 'We couldn’t load your agent workspace.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(agentWorkspaceProvider),
                  child: Text(es ? 'Reintentar' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final fleets = reviewRows(data['fleets']);
          final selected =
              fleets.where((f) => f['id'] == fleet).firstOrNull ??
              (fleets.length == 1 ? fleets.first : null);
          final client = selected?['id'] as String?;
          final connections = reviewRows(
            data['connections'],
          ).where((c) => c['client_id'] == client).toList();
          final active = connections
              .where(
                (c) =>
                    c['revoked_at'] == null &&
                    DateTime.tryParse(
                          c['expires_at']?.toString() ?? '',
                        )?.isAfter(DateTime.now()) ==
                        true,
              )
              .length;
          final ids = connections.map((c) => c['id']).toSet();
          final events = reviewRows(
            data['activity'],
          ).where((e) => ids.contains(e['connection_id'])).take(8).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        es
                            ? 'Mantenimiento con evidencia'
                            : 'Maintenance, with evidence',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        es
                            ? 'Revisa las propuestas de tu agente junto al manual y al historial del equipo.'
                            : 'Review your agent’s proposals alongside the manual and equipment history.',
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        key: ValueKey(client),
                        initialValue: client,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: es ? 'Flota de trabajo' : 'Working fleet',
                        ),
                        items: fleets
                            .map(
                              (f) => DropdownMenuItem(
                                value: f['id'] as String,
                                child: Text(f['name'] as String),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => fleet = value),
                      ),
                      const SizedBox(height: 20),
                      if (client == null)
                        AgentSectionCard(
                          title: es
                              ? 'Elige dónde trabajar'
                              : 'Choose where to work',
                          icon: Icons.domain_outlined,
                          child: Text(
                            fleets.isEmpty
                                ? (es
                                      ? 'Agrega un equipo antes de preparar planes con un agente.'
                                      : 'Add an asset before preparing plans with an agent.')
                                : (es
                                      ? 'Selecciona una flota para ver sus propuestas, manuales y actividad.'
                                      : 'Select a fleet to see its proposals, manuals and activity.'),
                          ),
                        ),
                      if (client != null) ...[
                        AgentSectionCard(
                          title: es ? 'Planes por revisar' : 'Plans to review',
                          icon: Icons.rate_review_outlined,
                          child: ref
                              .watch(pendingAgentPlansProvider((client, 0)))
                              .when(
                                loading: () => const LinearProgressIndicator(),
                                error: (_, __) => TextButton(
                                  onPressed: () => ref.invalidate(
                                    pendingAgentPlansProvider((client, 0)),
                                  ),
                                  child: Text(
                                    es
                                        ? 'No se pudieron cargar los planes. Reintentar.'
                                        : 'Could not load plans. Retry.',
                                  ),
                                ),
                                data: (plans) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (plans.isEmpty) ...[
                                      Text(
                                        es
                                            ? 'No hay planes pendientes'
                                            : 'No plans waiting',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        es
                                            ? 'Agrega un manual y pide a tu agente conectado que prepare un plan para el equipo.'
                                            : 'Add a manual and ask your connected agent to prepare a plan for the equipment.',
                                      ),
                                    ] else ...[
                                      Text(
                                        plans.first['draft']['interval_label']
                                            as String,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      Text(
                                        '${plans.first['assets']?['name'] ?? ''} · ${reviewHours(plans.first['draft']['interval_hours'] as num?)}',
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: () => _review(
                                          plans.first['id'] as String,
                                          client,
                                        ),
                                        icon: const Icon(Icons.arrow_forward),
                                        label: Text(
                                          es
                                              ? 'Revisar siguiente plan'
                                              : 'Review next plan',
                                        ),
                                      ),
                                      for (final plan in plans.skip(1).take(2))
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            plan['draft']['interval_label']
                                                as String,
                                          ),
                                          subtitle: Text(
                                            plan['assets']?['name']
                                                    as String? ??
                                                '',
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                          ),
                                          onTap: () => _review(
                                            plan['id'] as String,
                                            client,
                                          ),
                                        ),
                                      if (plans.length > 1)
                                        TextButton(
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    AgentPendingPlansScreen(
                                                      fleet: client,
                                                    ),
                                              ),
                                            );
                                            if (mounted) {
                                              ref.invalidate(
                                                pendingAgentPlansProvider((
                                                  client,
                                                  0,
                                                )),
                                              );
                                            }
                                          },
                                          child: Text(
                                            es
                                                ? 'Ver todos los planes pendientes'
                                                : 'View all pending plans',
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                        ),
                        AgentSectionCard(
                          title: es
                              ? 'Fuentes y procedimientos'
                              : 'Sources and procedures',
                          icon: Icons.menu_book_outlined,
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.document_scanner_outlined,
                                ),
                                title: Text(
                                  es
                                      ? 'Manuales del equipo'
                                      : 'Equipment manuals',
                                ),
                                subtitle: Text(
                                  es
                                      ? 'Escanear, importar PDF o consultar páginas'
                                      : 'Scan, import a PDF or look up source pages',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => MaintenanceDocumentsScreen(
                                      fleet: client,
                                      fleetName: selected!['name'] as String,
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.checklist),
                                title: Text(
                                  es
                                      ? 'Listas PM y preoperativas'
                                      : 'PM and pre-op checklists',
                                ),
                                subtitle: Text(
                                  es
                                      ? 'Revisar borradores y publicar procedimientos'
                                      : 'Review drafts and publish procedures',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  ref.invalidate(checklistLibraryProvider);
                                  context.push('/checklist-library');
                                },
                              ),
                            ],
                          ),
                        ),
                        AgentSectionCard(
                          title: es
                              ? 'Tu agente conectado'
                              : 'Your connected agent',
                          icon: Icons.link,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                active == 0
                                    ? (es
                                          ? 'Sin conexiones activas'
                                          : 'No active connections')
                                    : '$active ${es ? 'conexiones activas visibles' : 'active connections shown'}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                es
                                    ? 'Conecta Codex, OpenClaw u otro agente compatible. Tú eliges sus permisos; revisas y activas los planes aquí.'
                                    : 'Connect Codex, OpenClaw or another compatible agent. You choose its permissions; review and activate plans here.',
                              ),
                              TextButton.icon(
                                onPressed: _connections,
                                icon: const Icon(Icons.tune),
                                label: Text(
                                  es
                                      ? 'Gestionar conexiones'
                                      : 'Manage connections',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (events.isNotEmpty)
                          AgentSectionCard(
                            title: es
                                ? 'Actividad reciente'
                                : 'Recent activity',
                            icon: Icons.history,
                            child: Column(
                              children: [
                                for (final event in events)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(activity(event, es)),
                                    subtitle: Text(
                                      '${event['label']} · ${reviewDate(context, event['created_at'])}',
                                    ),
                                    trailing: event['result_id'] == null
                                        ? null
                                        : const Icon(Icons.chevron_right),
                                    onTap: event['result_id'] == null
                                        ? null
                                        : () {
                                            if (event['action'] ==
                                                'create_plan_draft') {
                                              _review(
                                                event['result_id'] as String,
                                                client,
                                              );
                                            } else if (event['action'] ==
                                                'create_checklist_draft') {
                                              ref.invalidate(
                                                checklistLibraryProvider,
                                              );
                                              context.push(
                                                '/checklist-library',
                                              );
                                            } else {
                                              context.push(
                                                '/maintenance/jobs/${event['result_id']}',
                                              );
                                            }
                                          },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
