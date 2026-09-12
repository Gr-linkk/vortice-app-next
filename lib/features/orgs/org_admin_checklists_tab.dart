import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';

class OrgAdminChecklistsTab extends ConsumerWidget {
  final String orgId;
  const OrgAdminChecklistsTab({super.key, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final assignments = ref.watch(orgChecklistAssignmentsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/checklist-library'),
              icon: const Icon(Icons.library_books_outlined),
              label: Text(
                es ? 'Abrir biblioteca de listas' : 'Open checklist library',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Expanded(
          child: assignments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () => ref.invalidate(orgChecklistAssignmentsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.checklist_outlined,
                          size: 56,
                          color: context.appColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          es
                              ? 'Aún no hay listas asignadas.'
                              : 'No checklists assigned yet.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          es
                              ? 'Abre la biblioteca para asignar una revisión previa a la operación o crear un trabajo de mantenimiento.'
                              : 'Open the checklist library to assign a pre-operation check or create a maintenance job.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final assignment = items[i];
                  final template =
                      assignment['checklist_templates']
                          as Map<String, dynamic>?;
                  final asset = assignment['assets'] as Map<String, dynamic>?;
                  final assignee =
                      assignment['assignee'] as Map<String, dynamic>?;
                  final status = assignment['status'] as String? ?? 'pending';
                  final statusLabel = switch (status) {
                    'completed' => es ? 'Completada' : 'Completed',
                    'in_progress' => es ? 'En curso' : 'In progress',
                    'cancelled' => es ? 'Cancelada' : 'Cancelled',
                    'pending' => es ? 'Pendiente' : 'Pending',
                    _ => es ? 'Estado desconocido' : 'Unknown status',
                  };
                  final color = orgAdminChecklistAssignmentStatusColor(
                    context.appColors,
                    status,
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template?['name'] as String? ??
                                (es ? 'Lista de verificación' : 'Checklist'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (assignee?['full_name'] != null)
                                assignee!['full_name'] as String,
                              if (asset?['name'] != null)
                                asset!['name'] as String,
                            ].join(' · '),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
