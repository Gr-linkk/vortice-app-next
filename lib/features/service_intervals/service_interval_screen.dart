import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/service_intervals/service_interval_add_sheet.dart';
import 'package:vortice_app/features/service_intervals/service_interval_asset_header.dart';
import 'package:vortice_app/features/service_intervals/service_interval_edit_sheet.dart';
import 'package:vortice_app/features/service_intervals/service_interval_list.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/features/service_intervals/service_interval_screen_support.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';

class ServiceIntervalScreen extends ConsumerStatefulWidget {
  final String? assetId;
  final bool readOnly;

  const ServiceIntervalScreen({
    super.key,
    this.assetId,
    this.readOnly = false,
  });

  @override
  ConsumerState<ServiceIntervalScreen> createState() =>
      _ServiceIntervalScreenState();
}

class _ServiceIntervalScreenState extends ConsumerState<ServiceIntervalScreen> {
  Asset? _selectedAsset;

  bool get _isFixedAsset => widget.assetId != null;

  @override
  Widget build(BuildContext context) {
    final fixedAssetAsync =
        _isFixedAsset ? ref.watch(assetByIdProvider(widget.assetId!)) : null;
    final assetsAsync = _isFixedAsset ? null : ref.watch(visibleAssetsProvider);
    ref.watch(checklistTemplatesProvider);
    final activeAsset =
        _isFixedAsset ? fixedAssetAsync?.valueOrNull : _selectedAsset;
    final activeAssetId = activeAsset?.id;

    final scaffold = Scaffold(
      appBar: AppBar(
        title:
            Text(widget.readOnly ? 'Parts & Maintenance' : 'Maintenance Plan'),
      ),
      floatingActionButton: widget.readOnly || activeAssetId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, activeAsset!),
              icon: const Icon(Icons.add),
              label: const Text('Add Interval'),
              backgroundColor: AppColors.primary,
            ),
      body: Column(
        children: [
          if (_isFixedAsset)
            fixedAssetAsync!.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
              ),
              data: (asset) => ServiceIntervalAssetHeader(asset: asset),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: assetsAsync!.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
                data: (assets) => DropdownButtonFormField<Asset>(
                  initialValue: _selectedAsset,
                  decoration: const InputDecoration(
                    labelText: 'Select Asset',
                    prefixIcon: Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: assets
                      .map((a) => DropdownMenuItem<Asset>(
                            value: a,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (a) => setState(() => _selectedAsset = a),
                ),
              ),
            ),
          Expanded(
            child: activeAssetId == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 56, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'Select an asset to manage its\nservice intervals.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ServiceIntervalList(
                    assetId: activeAssetId,
                    asset: activeAsset,
                    readOnly: widget.readOnly,
                    onEdit: widget.readOnly
                        ? null
                        : (summary) => _showEditSheet(
                              context,
                              activeAsset!,
                              summary,
                            ),
                  ),
          ),
        ],
      ),
    );

    return ClientCapabilityGate(
      clientId: activeAsset?.clientId,
      capability: ClientCapability.maintenancePlanning,
      allowedBuilder: (_) => scaffold,
      blockedBuilder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Maintenance Plan')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: ClientCapabilityDisabledPanel(
              capability: ClientCapability.maintenancePlanning,
              message:
                  'Maintenance planning is not enabled for this client. Existing service history remains available read-only.',
            ),
          ),
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, Asset asset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ServiceIntervalAddSheet(
        assetId: asset.id,
        templates: maintenanceTemplatesForAsset(
          ref.read(checklistTemplatesProvider).valueOrNull ?? const [],
          asset,
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    Asset asset,
    ServiceIntervalSummary summary,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ServiceIntervalEditSheet(
        assetId: asset.id,
        summary: summary,
        templates: maintenanceTemplatesForAsset(
          ref.read(checklistTemplatesProvider).valueOrNull ?? const [],
          asset,
        ),
      ),
    );
  }
}
