import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'agent_plan_review_screen.dart';

final pendingAgentPlansProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String, int)>(
      (ref, key) =>
          ref.watch(agentPlanRepositoryProvider).pending(key.$1, key.$2),
    );

class AgentPendingPlansScreen extends ConsumerStatefulWidget {
  const AgentPendingPlansScreen({super.key, required this.fleet});
  final String fleet;
  @override
  ConsumerState<AgentPendingPlansScreen> createState() => _PendingPlansState();
}

class _PendingPlansState extends ConsumerState<AgentPendingPlansScreen> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final provider = pendingAgentPlansProvider((widget.fleet, page));
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Planes por revisar' : 'Plans to review'),
        actions: [
          IconButton(
            tooltip: es ? 'Actualizar' : 'Refresh',
            onPressed: () => ref.invalidate(provider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(provider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(
                  es
                      ? 'No se pudo cargar. Reintentar.'
                      : 'Could not load. Retry.',
                ),
              ),
            ),
            data: (rows) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  es
                      ? 'Propuestas pendientes de tu revisión. Comprueba el manual, las horas actuales y el último servicio antes de activar cada plan.'
                      : 'Proposals waiting for your review. Check the manual, current hours and last service before activating each plan.',
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      es
                          ? 'No hay propuestas en esta página.'
                          : 'No proposals on this page.',
                    ),
                  ),
                for (final row in rows.take(25))
                  Card(
                    child: ListTile(
                      title: Text(row['draft']['interval_label'] as String),
                      subtitle: Text(
                        '${row['assets']?['name'] ?? ''}\n${row['draft']['interval_hours']} h',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AgentPlanReviewScreen(id: row['id'] as String),
                          ),
                        );
                        if (mounted) ref.invalidate(provider);
                      },
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    if (page > 0)
                      TextButton(
                        onPressed: () => setState(() => page--),
                        child: Text(es ? 'Anterior' : 'Previous'),
                      ),
                    if (rows.length > 25)
                      TextButton(
                        onPressed: () => setState(() => page++),
                        child: Text(es ? 'Siguiente' : 'Next'),
                      ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
