import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';

final fleetRepositoryProvider = Provider<FleetRepository>(
  (ref) => SupabaseFleetRepository(supabase),
);

final fleetAssetsProvider = FutureProvider.autoDispose<List<FleetAsset>>((
  ref,
) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return [];
  return ref.watch(fleetRepositoryProvider).fleet();
});
final fleetFaultsProvider = FutureProvider.autoDispose
    .family<List<FleetFault>, String?>((ref, assetId) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(fleetRepositoryProvider).faults(assetId: assetId);
    });
final fleetFaultProvider = FutureProvider.autoDispose
    .family<FleetFault?, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return null;
      final rows = await ref.watch(fleetRepositoryProvider).faults(faultId: id);
      return rows.firstOrNull;
    });
final faultEventsProvider = FutureProvider.autoDispose
    .family<List<FleetEvent>, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(fleetRepositoryProvider).faultEvents(id);
    });
final availabilityEventsProvider = FutureProvider.autoDispose
    .family<List<FleetEvent>, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(fleetRepositoryProvider).availabilityEvents(id);
    });
final fleetAssigneesProvider = FutureProvider.autoDispose
    .family<List<FleetMember>, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(fleetRepositoryProvider).assignees(id);
    });

void refreshFleet(WidgetRef ref, {String? faultId, String? assetId}) {
  ref.invalidate(fleetAttentionProvider);
  ref.invalidate(assetHistoryProvider);
  ref.invalidate(coordinationThreadProvider);
  ref.invalidate(fleetAssetsProvider);
  ref.invalidate(fleetFaultsProvider);
  ref.invalidate(openMaintenanceRequestsProvider);
  ref.invalidate(clientFlaggedIssuesProvider);
  if (assetId != null) {
    ref.invalidate(maintenanceRequestsForAssetProvider(assetId));
  }
  if (faultId != null) {
    ref.invalidate(fleetFaultProvider(faultId));
    ref.invalidate(faultEventsProvider(faultId));
  }
  if (assetId != null) ref.invalidate(availabilityEventsProvider(assetId));
}
