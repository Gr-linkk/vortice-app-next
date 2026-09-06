import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
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
    final es = Localizations.localeOf(context).languageCode == 'es';
    final title = es ? 'Informes de servicio' : 'Service Reports';

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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: reportsAsync.when(
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      es ? 'Cargando informes...' : 'Loading asset records...',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
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
                      es
                          ? 'Informes no disponibles.'
                          : 'Service report records unavailable.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                data: (reports) {
                  final latest = reports.isEmpty ? null : reports.first.date;
                  final countLabel = es
                      ? '${reports.length} informe${reports.length == 1 ? '' : 's'}'
                      : '${reports.length} report${reports.length == 1 ? '' : 's'}';
                  final subtitle = reports.isEmpty
                      ? (es
                            ? 'Aún no hay informes de servicio'
                            : 'No service reports attached yet')
                      : '$countLabel${latest == null ? '' : ' • ${es ? 'último' : 'latest'} ${DateFormat.yMMMd(es ? 'es' : 'en').format(latest.toLocal())}'}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
