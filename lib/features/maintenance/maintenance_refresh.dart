import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/checklists/saved_checklists_provider.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'maintenance_repository.dart';

void refreshMaintenance(
  WidgetRef ref, {
  String? jobId,
  bool assetsChanged = false,
}) {
  ref.invalidate(maintenanceJobsProvider);
  ref.invalidate(maintenanceAssetProvider);
  if (jobId != null) ref.invalidate(maintenanceJobProvider(jobId));
  ref.invalidate(remindersProvider);
  if (assetsChanged) {
    ref.invalidate(maintenanceWorkspaceProvider);
    ref.invalidate(currentClientFleetAssetsProvider);
    ref.invalidate(assetsProvider);
    ref.invalidate(visibleAssetsProvider);
    ref.invalidate(assetByIdProvider);
    ref.invalidate(fleetAssetsProvider);
  }
  // Saved maintenance history is shared with the existing asset history screen.
  ref.invalidate(savedChecklistsForAssetProvider);
}
