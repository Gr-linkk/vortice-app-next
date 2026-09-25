import 'package:flutter/material.dart';
import 'asset_workflow_policy.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'asset_workspace.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key, this.initialFilter = 'all'});
  final String initialFilter;

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  final _search = TextEditingController();
  String _searchQuery = '';
  late String _filter;
  @override
  void initState() {
    super.initState();
    _filter = assetWorkspaceFilters.containsKey(widget.initialFilter)
        ? widget.initialFilter
        : 'all';
  }

  @override
  void didUpdateWidget(covariant AssetListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = assetWorkspaceFilters.containsKey(widget.initialFilter)
          ? widget.initialFilter
          : 'all';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(visibleAssetsProvider);
    final workspace = ref.watch(assetWorkspaceProvider);
    final es = isSpanish(context);
    final fr = isFrench(context);
    final types =
        ref.watch(assetTypesProvider).valueOrNull ?? const <AssetType>[];
    final typeNames = {for (final type in types) type.id: type.name};
    final assignedProfilesAsync = ref.watch(assetAssignedProfilesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final canAdd = AssetWorkflowPolicy.canManageProfile(profile);
    final showAssignedClient =
        !(profile?.membershipManaged ?? false) &&
        (canAdd || profile?.role == UserRole.employee);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetsTitle),
        actions: [
          if (canAdd)
            PopupMenuButton<String>(
              tooltip: localizedText(
                context,
                'More actions',
                'Más acciones',
                'Plus d’actions',
              ),
              onSelected: (_) => context.push('/assets/import'),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  child: Text(
                    localizedText(
                      context,
                      'Import equipment',
                      'Importar equipos',
                      'Importer des équipements',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: l10n.searchAssets,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: localizedText(
                              context,
                              'Clear search',
                              'Borrar búsqueda',
                              'Effacer la recherche',
                            ),
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
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  key: ValueKey(_filter),
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: localizedText(
                      context,
                      'Show assets',
                      'Mostrar equipos',
                      'Afficher les équipements',
                    ),
                    isDense: true,
                  ),
                  items: [
                    for (final entry in assetWorkspaceFilters.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          '${fr
                              ? entry.value.$3
                              : es
                              ? entry.value.$2
                              : entry.value.$1}${workspace.hasValue ? ' (${filterWorkspaceAssets(workspace.value!, entry.key).length})' : ''}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _filter = value);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: assetsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => AppErrorState(
                error: err,
                onRetry: () => ref.invalidate(visibleAssetsProvider),
              ),
              data: (assets) {
                if (_filter != 'all' && !workspace.hasValue) {
                  return workspace.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => AppErrorState(
                      error: error,
                      onRetry: () => ref.invalidate(assetWorkspaceProvider),
                    ),
                    data: (_) => const SizedBox.shrink(),
                  );
                }
                final matchingIds = workspace.hasValue
                    ? filterWorkspaceAssets(
                        workspace.value!,
                        _filter,
                      ).map((r) => r['id']).toSet()
                    : null;
                final workspaceRows = {
                  for (final row in filterWorkspaceAssets(
                    workspace.valueOrNull ?? {},
                    'all',
                  ))
                    row['id']: row,
                };
                final assignedProfiles =
                    assignedProfilesAsync.valueOrNull ?? {};
                final filtered = assets.where((a) {
                  final assignedProfile = assignedProfiles[a.clientId];
                  final assignedLabel = _assignedProfileLabel(assignedProfile);
                  final query = _searchQuery.trim().toLowerCase();
                  final matchesQuery =
                      _searchQuery.isEmpty ||
                      a.name.toLowerCase().contains(query) ||
                      (a.model?.toLowerCase().contains(query) ?? false) ||
                      (a.serialNumber?.toLowerCase().contains(query) ??
                          false) ||
                      (assignedLabel?.toLowerCase().contains(query) ?? false);
                  return matchesQuery &&
                      (_filter == 'all' || matchingIds?.contains(a.id) == true);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.trim().isNotEmpty || _filter != 'all'
                          ? localizedText(
                              context,
                              'No matching assets. Try another name or clear the search.',
                              'No hay coincidencias. Prueba otro nombre o borra la búsqueda.',
                              'Aucun équipement trouvé. Essayez un autre nom ou effacez la recherche.',
                            )
                          : l10n.noAssets,
                      style: TextStyle(color: context.appColors.textSecondary),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(visibleAssetsProvider);
                    ref.invalidate(assetWorkspaceProvider);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _AssetListTile(
                      asset: filtered[i],
                      typeName: typeNames[filtered[i].assetTypeId],
                      assignedProfile: showAssignedClient
                          ? assignedProfiles[filtered[i].clientId]
                          : null,
                      showAssignedClient: showAssignedClient,
                      attentionLabel: _filter == 'all'
                          ? null
                          : (fr
                                ? assetWorkspaceFilters[_filter]!.$3
                                : es
                                ? assetWorkspaceFilters[_filter]!.$2
                                : assetWorkspaceFilters[_filter]!.$1),
                      openWork:
                          (workspaceRows[filtered[i].id]?['open_work'] as num?)
                              ?.toInt(),
                      onTap: () => context.push('/assets/${filtered[i].id}'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/assets/new'),
              backgroundColor: context.appColors.primary,
              icon: const Icon(Icons.add),
              label: Text(
                localizedText(
                  context,
                  'Add asset',
                  'Añadir equipo',
                  'Ajouter un équipement',
                ),
              ),
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
    final label =
        _assignedProfileLabel(profile) ??
        localizedText(
          context,
          'Unassigned / unknown',
          'Sin asignar / desconocido',
          'Non attribué / inconnu',
        );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(
            Icons.business_outlined,
            size: 12,
            color: context.appColors.textSecondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              localizedText(
                context,
                'Assigned to $label',
                'Asignado a $label',
                'Attribué à $label',
              ),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appColors.textSecondary,
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
  final String? typeName;
  final Profile? assignedProfile;
  final bool showAssignedClient;
  final VoidCallback onTap;
  final String? attentionLabel;
  final int? openWork;

  const _AssetListTile({
    required this.asset,
    required this.typeName,
    required this.assignedProfile,
    required this.showAssignedClient,
    required this.onTap,
    this.attentionLabel,
    this.openWork,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: EquipmentIllustration(
          assetTypeId: asset.assetTypeId,
          typeName: typeName,
          size: 56,
        ),
        title: Text(asset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attentionLabel != null)
              Text(
                attentionLabel!,
                style: TextStyle(color: context.appColors.warning),
              ),
            if (openWork != null && openWork! > 0)
              Text(
                localizedText(
                  context,
                  '$openWork open work orders',
                  '$openWork trabajos abiertos',
                  '$openWork bons de travail ouverts',
                ),
              ),
            if (showAssignedClient)
              _AssignedClientLine(profile: assignedProfile),
            if (asset.model != null || asset.make != null)
              Text(
                [asset.make, asset.model].whereType<String>().join(' · '),
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            if (asset.location != null)
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 12,
                    color: context.appColors.textSecondary,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      asset.location!,
                      style: TextStyle(
                        color: context.appColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: context.appColors.textSecondary,
        ),
        onTap: onTap,
        isThreeLine: showAssignedClient || asset.location != null,
      ),
    );
  }
}
