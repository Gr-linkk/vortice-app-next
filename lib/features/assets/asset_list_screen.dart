import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/asset_icons.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key});

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(assetsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final canAdd =
        profile?.role == UserRole.owner || profile?.role == UserRole.employee;

    final prefix = switch (profile?.role) {
      UserRole.owner => '/owner',
      UserRole.client => '/client',
      _ => '/owner',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchAssets,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: assetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(err.toString()),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(assetsProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (assets) {
          final filtered = assets.where((a) {
            final matchesQuery = _searchQuery.isEmpty ||
                a.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (a.model?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                    false) ||
                (a.serialNumber
                        ?.toLowerCase()
                        .contains(_searchQuery.toLowerCase()) ??
                    false);
            return matchesQuery;
          }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(l10n.noAssets,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(assetsProvider),
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) => _AssetListTile(
                asset: filtered[i],
                onTap: () => context.push('$prefix/assets/${filtered[i].id}'),
              ),
            ),
          );
        },
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              onPressed: () => context.push('$prefix/assets/add'),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _AssetListTile extends StatelessWidget {
  final Asset asset;
  final VoidCallback onTap;

  const _AssetListTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Icon(assetIconFor(asset.assetTypeId),
              color: AppColors.primary, size: 22),
        ),
        title: Text(asset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset.model != null || asset.make != null)
              Text(
                [asset.make, asset.model].whereType<String>().join(' · '),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            if (asset.location != null)
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 2),
                  Text(
                    asset.location!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
          ],
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
        isThreeLine: asset.location != null,
      ),
    );
  }
}
