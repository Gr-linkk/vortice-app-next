import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/assets/asset_detail_row.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/models/asset.dart';

class AssetClientAssignRow extends ConsumerWidget {
  final Asset asset;

  const AssetClientAssignRow({super.key, required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedProfilesAsync = ref.watch(assetAssignedProfilesProvider);

    return assignedProfilesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profiles) {
        final assigned = profiles[asset.clientId];
        final label = assigned == null
            ? 'Unassigned / unknown'
            : assigned.fullName.trim().isNotEmpty
                ? assigned.fullName
                : assigned.email;

        return AssetDetailRow(label: 'Client', value: label);
      },
    );
  }
}
