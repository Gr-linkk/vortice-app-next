import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class AssetEnginesCard extends ConsumerWidget {
  final String assetId;
  final String routePrefix;

  const AssetEnginesCard({
    super.key,
    required this.assetId,
    required this.routePrefix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));
    final count = enginesAsync.valueOrNull?.length ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('$routePrefix/assets/$assetId/engines'),
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
            Icon(Icons.engineering, color: context.appColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.enginesTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '$count ${l10n.enginesCount}',
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.appColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
