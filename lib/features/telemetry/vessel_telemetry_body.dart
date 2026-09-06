import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_engine_info_section.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_fault_codes_section.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_live_gauges_section.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_maintenance_section.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_service_history_section.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/asset_engine.dart';

class VesselTelemetryBody extends ConsumerWidget {
  final Asset asset;
  final AsyncValue<List<AssetEngine>> enginesAsync;
  final AssetEngine? selectedEngine;
  final ValueChanged<AssetEngine> onEngineSelected;

  const VesselTelemetryBody({
    super.key,
    required this.asset,
    required this.enginesAsync,
    required this.selectedEngine,
    required this.onEngineSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return enginesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(friendlyError(context, err),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (engines) {
        final engine =
            selectedEngine ?? (engines.isNotEmpty ? engines.first : null);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(latestTelemetryForAssetProvider(asset.id));
            ref.invalidate(alertsForAssetProvider(asset.id));
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (engines.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: engines.length,
                    itemBuilder: (_, i) {
                      final e = engines[i];
                      final selected = engine?.id == e.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.label),
                          selected: selected,
                          onSelected: (_) => onEngineSelected(e),
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              VesselTelemetryLiveGaugesSection(assetId: asset.id),
              VesselTelemetryFaultCodesSection(assetId: asset.id),
              if (engine != null)
                VesselTelemetryEngineInfoSection(engine: engine),
              VesselTelemetryMaintenanceSection(assetId: asset.id),
              VesselTelemetryServiceHistorySection(assetId: asset.id),
            ],
          ),
        );
      },
    );
  }
}
