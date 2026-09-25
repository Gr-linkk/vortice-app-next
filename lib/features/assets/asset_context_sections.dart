import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/assurance/assurance_form.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';

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
            localizedText(
              context,
              'Current work unavailable',
              'Trabajo actual no disponible',
              'Travail en cours indisponible',
            ),
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
                title: Text(
                  localizedText(
                    context,
                    'Current work',
                    'Trabajo actual',
                    'Travail en cours',
                  ),
                ),
                subtitle: Text(
                  localizedText(
                    context,
                    '${open.length} open work orders',
                    '${open.length} órdenes abiertas',
                    '${open.length} bons de travail ouverts',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push('/maintenance/planning?assetId=$assetId'),
              ),
              for (final job in open.take(3))
                ListTile(
                  dense: true,
                  title: Text(job.title),
                  subtitle: Text(
                    job.lifecycleLabel(es, french: isFrench(context)),
                  ),
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
              localizedText(
                context,
                'Location unavailable',
                'Ubicación no disponible',
                'Emplacement indisponible',
              ),
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
                      localizedText(
                        context,
                        'No location recorded',
                        'Sin ubicación registrada',
                        'Aucun emplacement enregistré',
                      ),
                ),
                subtitle: Text(
                  '${custody['responsible_name'] ?? localizedText(context, 'No responsible person', 'Sin responsable', 'Aucune personne responsable')} · ${assuranceLabel(custody['lifecycle'] as String? ?? 'active', es, french: isFrench(context))}',
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
              localizedText(
                context,
                'Inspections & certificates',
                'Inspecciones y certificados',
                'Inspections et certificats',
              ),
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
                    localizedText(
                      context,
                      'Retry inspections',
                      'Reintentar inspecciones',
                      'Réessayer de charger les inspections',
                    ),
                  ),
                ),
                data: (items) => Column(
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          localizedText(
                            context,
                            'No inspections configured.',
                            'No hay inspecciones configuradas.',
                            'Aucune inspection n’est configurée.',
                          ),
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
                            french: isFrench(context),
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
