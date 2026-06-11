import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset.dart';

class AssetStartChecklistCard extends StatelessWidget {
  final Asset asset;
  final String routePrefix;

  const AssetStartChecklistCard({
    super.key,
    required this.asset,
    required this.routePrefix,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(
        '$routePrefix/assets/${asset.id}/checklists/new?clientId=${Uri.encodeComponent(asset.clientId)}&name=${Uri.encodeComponent(asset.name)}&assetTypeId=${Uri.encodeComponent(asset.assetTypeId)}',
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
            const Icon(Icons.playlist_add_check_circle_outlined,
                color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start Checklist',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Text(
                    'Save a checklist to this asset history',
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
