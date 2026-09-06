import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/user_feedback.dart';
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
  final _search = TextEditingController();
  String _searchQuery = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final assignedProfilesAsync = ref.watch(assetAssignedProfilesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final canAdd = profile?.role == UserRole.owner;
    final showAssignedClient = canAdd || profile?.role == UserRole.employee;
    final prefix = roleRoutePrefix(profile?.role ?? UserRole.client);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.searchAssets,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: isSpanish(context)
                            ? 'Borrar búsqueda'
                            : 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _searchQuery = '';
                        }),
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: assetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorState(
          error: err,
          onRetry: () => ref.invalidate(visibleAssetsProvider),
        ),
        data: (assets) {
          final assignedProfiles = assignedProfilesAsync.valueOrNull ?? {};
          final filtered = assets.where((a) {
            final assignedProfile = assignedProfiles[a.clientId];
            final assignedLabel = _assignedProfileLabel(assignedProfile);
            final query = _searchQuery.trim().toLowerCase();
            final matchesQuery =
                _searchQuery.isEmpty ||
                a.name.toLowerCase().contains(query) ||
                (a.model?.toLowerCase().contains(query) ?? false) ||
                (a.serialNumber?.toLowerCase().contains(query) ?? false) ||
                (assignedLabel?.toLowerCase().contains(query) ?? false);
            return matchesQuery;
          }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _searchQuery.trim().isNotEmpty
                    ? (isSpanish(context)
                          ? 'No hay coincidencias. Prueba otro nombre o borra la búsqueda.'
                          : 'No matching assets. Try another name or clear the search.')
                    : l10n.noAssets,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(visibleAssetsProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _AssetListTile(
                asset: filtered[i],
                assignedProfile: showAssignedClient
                    ? assignedProfiles[filtered[i].clientId]
                    : null,
                showAssignedClient: showAssignedClient,
                onTap: () => context.push('$prefix/assets/${filtered[i].id}'),
              ),
            ),
          );
        },
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => context.push('$prefix/assets/add'),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add),
              label: Text(isSpanish(context) ? 'Añadir equipo' : 'Add asset'),
            )
          : null,
    );
  }
}

String? _assignedProfileLabel(Profile? profile) {
  if (profile == null) return null;
  final name = profile.fullName.trim();
  if (name.isNotEmpty) return name;
  return profile.email;
}

class _AssignedClientLine extends StatelessWidget {
  final Profile? profile;

  const _AssignedClientLine({required this.profile});

  @override
  Widget build(BuildContext context) {
    final label = _assignedProfileLabel(profile) ?? 'Unassigned / unknown';
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          const Icon(
            Icons.business_outlined,
            size: 12,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              'Assigned to $label',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetListTile extends StatelessWidget {
  final Asset asset;
  final Profile? assignedProfile;
  final bool showAssignedClient;
  final VoidCallback onTap;

  const _AssetListTile({
    required this.asset,
    required this.assignedProfile,
    required this.showAssignedClient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Icon(
            assetIconFor(asset.assetTypeId),
            color: AppColors.primary,
            size: 22,
          ),
        ),
        title: Text(asset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAssignedClient)
              _AssignedClientLine(profile: assignedProfile),
            if (asset.model != null || asset.make != null)
              Text(
                [asset.make, asset.model].whereType<String>().join(' · '),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            if (asset.location != null)
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      asset.location!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
        isThreeLine: showAssignedClient || asset.location != null,
      ),
    );
  }
}
