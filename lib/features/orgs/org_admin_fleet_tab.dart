import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/models/asset.dart';

class OrgAdminFleetTab extends ConsumerWidget {
  final String ownerProfileId;

  const OrgAdminFleetTab({super.key, required this.ownerProfileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsProvider);

    return assetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          err.toString(),
          style: const TextStyle(color: AppColors.error),
        ),
      ),
      data: (assets) {
        final orgAssets =
            assets.where((a) => a.clientId == ownerProfileId).toList();

        if (orgAssets.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_boat_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No fleet assets.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orgAssets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _OrgAdminAssetCard(asset: orgAssets[i]),
        );
      },
    );
  }
}

class _OrgAdminAssetCard extends StatelessWidget {
  final Asset asset;

  const _OrgAdminAssetCard({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_boat, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                if (asset.model != null)
                  Text(
                    asset.model!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline,
              color: AppColors.textSecondary, size: 16),
        ],
      ),
    );
  }
}
