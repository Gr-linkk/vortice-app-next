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
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(
            BorderSide(color: context.appColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.playlist_add_check_circle_outlined,
              color: context.appColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Checklist',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Save a checklist to this asset history',
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
