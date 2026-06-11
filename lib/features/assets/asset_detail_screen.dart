import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_detail_body.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/assets/edit_asset_screen.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class AssetDetailScreen extends ConsumerWidget {
  final String assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetAsync = ref.watch(assetByIdProvider(assetId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final canEdit = AssetWorkflowPolicy.canManageAsset(profile?.role);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetDetail),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.edit,
              onPressed: () async {
                final asset = assetAsync.valueOrNull;
                if (asset == null) return;
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditAssetScreen(asset: asset),
                  ),
                );
                if (updated == true) {
                  ref.invalidate(assetByIdProvider(assetId));
                }
              },
            ),
          if (canEdit)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text(l10n.confirmDelete),
                      content: Text(l10n.confirmDeleteMessage),
                      actions: [
                        TextButton(
                          onPressed: () => ctx.pop(false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => ctx.pop(true),
                          child: Text(l10n.delete,
                              style: const TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref
                        .read(assetControllerProvider.notifier)
                        .deleteAsset(assetId);
                    if (context.mounted) context.pop();
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.delete,
                          style: const TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: assetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (asset) {
          if (asset == null) {
            return Center(child: Text(l10n.assetNotFound));
          }
          return AssetDetailBody(asset: asset);
        },
      ),
    );
  }
}
