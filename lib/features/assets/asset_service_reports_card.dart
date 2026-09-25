import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/models/asset.dart';

class AssetServiceReportsCard extends ConsumerWidget {
  final Asset asset;
  final String routePrefix;

  const AssetServiceReportsCard({
    super.key,
    required this.asset,
    required this.routePrefix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(
      serviceReportIndexProvider((assetId: asset.id, workOrderId: null)),
    );
    final title = localizedText(
      context,
      'Service reports',
      'Informes de servicio',
      'Rapports d’intervention',
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        context.push(
          '$routePrefix/service-reports?assetId=${Uri.encodeComponent(asset.id)}',
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(
            BorderSide(color: context.appColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.description_outlined, color: context.appColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: reportsAsync.when(
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      localizedText(
                        context,
                        'Loading asset records...',
                        'Cargando informes...',
                        'Chargement des dossiers d’équipement…',
                      ),
                      style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                error: (_, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      localizedText(
                        context,
                        'Service report records unavailable.',
                        'Informes no disponibles.',
                        'Rapports d’intervention indisponibles.',
                      ),
                      style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                data: (reports) {
                  final latest = reports.isEmpty ? null : reports.first.date;
                  final countLabel = localizedText(
                    context,
                    '${reports.length} report${reports.length == 1 ? '' : 's'}',
                    '${reports.length} informe${reports.length == 1 ? '' : 's'}',
                    '${reports.length} rapport${reports.length == 1 ? '' : 's'}',
                  );
                  final subtitle = reports.isEmpty
                      ? localizedText(
                          context,
                          'No service reports attached yet',
                          'Aún no hay informes de servicio',
                          'Aucun rapport d’intervention n’est encore associé',
                        )
                      : '$countLabel${latest == null ? '' : ' • ${localizedText(context, 'latest', 'último', 'dernier')} ${DateFormat.yMMMd(appLocaleCode(context)).format(latest.toLocal())}'}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Icon(Icons.chevron_right, color: context.appColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
