import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/assurance/assurance_form.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/core/user_feedback.dart';

class AssetCurrentWorkSection extends ConsumerWidget {
  const AssetCurrentWorkSection({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final data = ref.watch(maintenancePlanningProvider(assetId));
    return Card(
      child: data.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => ListTile(
          title: Text(
            es ? 'Trabajo actual no disponible' : 'Current work unavailable',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(maintenancePlanningProvider(assetId)),
          ),
        ),
        data: (page) {
          final open = page.jobs.where((job) => !job.completed).toList();
          return Column(
            children: [
              ListTile(
                title: Text(es ? 'Trabajo actual' : 'Current work'),
                subtitle: Text(
                  es
                      ? '${open.length} órdenes abiertas'
                      : '${open.length} open work orders',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push('/maintenance/planning?assetId=$assetId'),
              ),
              for (final job in open.take(3))
                ListTile(
                  dense: true,
                  title: Text(job.title),
                  subtitle: Text(job.lifecycleLabel(es)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(job.route),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AssetCustodySection extends ConsumerWidget {
  const AssetCustodySection({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    return ref
        .watch(assuranceContextProvider(assetId))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => ListTile(
            title: Text(
              es ? 'Ubicación no disponible' : 'Location unavailable',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.invalidate(assuranceContextProvider(assetId)),
            ),
          ),
          data: (data) {
            final custody = data['custody'] as Map? ?? {};
            final asset = data['asset'] as Map? ?? {};
            return Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(
                  custody['site'] as String? ??
                      asset['location'] as String? ??
                      (es
                          ? 'Sin ubicación registrada'
                          : 'No location recorded'),
                ),
                subtitle: Text(
                  '${custody['responsible_name'] ?? (es ? 'Sin responsable' : 'No responsible person')} · ${assuranceLabel(custody['lifecycle'] as String? ?? 'active', es)}',
                ),
                trailing: data['can_manage'] == true
                    ? const Icon(Icons.edit_outlined)
                    : null,
                onTap: data['can_manage'] != true
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<bool>(
                            builder: (_) => AssuranceForm(
                              action: 'transfer',
                              asset: assetId,
                              catalog: data,
                            ),
                          ),
                        );
                        if (context.mounted) {
                          ref.invalidate(assuranceContextProvider(assetId));
                        }
                      },
              ),
            );
          },
        );
  }
}

class AssetInspectionsSection extends ConsumerWidget {
  const AssetInspectionsSection({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(
              es ? 'Inspecciones y certificados' : 'Inspections & certificates',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/assurance/assets/$assetId'),
          ),
          ref
              .watch(inspectionRegisterProvider(assetId))
              .when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => TextButton(
                  onPressed: () =>
                      ref.invalidate(inspectionRegisterProvider(assetId)),
                  child: Text(
                    es ? 'Reintentar inspecciones' : 'Retry inspections',
                  ),
                ),
                data: (items) => Column(
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          es
                              ? 'No hay inspecciones configuradas.'
                              : 'No inspections configured.',
                        ),
                      ),
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text(item['title'] as String? ?? ''),
                        subtitle: Text(
                          assuranceLabel(
                            inspectionState(item, DateTime.now()),
                            es,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          item['open_work_order_id'] == null
                              ? '/assurance/assets/$assetId'
                              : '/maintenance/jobs/${item['open_work_order_id']}',
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
