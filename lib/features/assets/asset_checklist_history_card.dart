import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset.dart';

class AssetChecklistHistoryCard extends StatelessWidget {
  final Asset asset;
  final String routePrefix;

  const AssetChecklistHistoryCard({
    super.key,
    required this.asset,
    required this.routePrefix,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(
        '$routePrefix/assets/${asset.id}/checklist-history?name=${Uri.encodeComponent(asset.name)}',
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
              BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.fact_check_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Checklist History',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Text(
                    'Saved maintenance and operations checklist records',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
