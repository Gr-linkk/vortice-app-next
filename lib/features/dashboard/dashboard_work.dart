import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';
import 'dashboard_layout.dart';

/// Uses the same account-scoped, offline-projected work as the Work screen.
List<WorkListEntry> dashboardCurrentWork(Iterable<WorkListEntry> entries) {
  final result = entries
      .where((entry) => entry.assignedToMe && !entry.completed)
      .toList();
  const ranks = {
    'in_progress': 0,
    'on_hold': 1,
    'assigned': 2,
    'draft': 3,
    'pending_review': 4,
  };
  result.sort((a, b) {
    final status = (ranks[a.status] ?? 3).compareTo(ranks[b.status] ?? 3);
    if (status != 0) return status;
    final due = (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
    return due != 0 ? due : a.id.compareTo(b.id);
  });
  return result;
}

class DashboardCurrentWork extends ConsumerWidget {
  const DashboardCurrentWork({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardSection(
          title: es ? 'Mi trabajo' : 'My work',
          onViewAll: () => context.push('/maintenance/planning?filter=mine'),
        ),
        ref
            .watch(workListProvider(null))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => AppErrorState(
                error: error,
                onRetry: () => ref.invalidate(workListProvider),
              ),
              data: (entries) {
                final work = dashboardCurrentWork(entries);
                if (work.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      es
                          ? 'No tienes \u00f3rdenes abiertas asignadas.'
                          : 'No open work orders assigned to you.',
                      style: TextStyle(color: context.appColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final entry in work.take(3))
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Icon(
                            entry.status == 'in_progress'
                                ? Icons.play_circle_outline
                                : Icons.build_outlined,
                            color: entry.status == 'on_hold'
                                ? context.appColors.warning
                                : context.appColors.primary,
                          ),
                          title: Text(entry.title),
                          subtitle: Text(
                            [
                              entry.assetName,
                              maintenanceStatus(entry.status, es),
                              if (entry.dueDate != null)
                                '${es ? 'Vence' : 'Due'} ${maintenanceDate(entry.dueDate, es)}',
                            ].where((value) => value.isNotEmpty).join(' \u00b7 '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await context.push(entry.route);
                            if (context.mounted) {
                              ref.invalidate(maintenanceJobsProvider);
                              ref.invalidate(workListProvider);
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
      ],
    );
  }
}
