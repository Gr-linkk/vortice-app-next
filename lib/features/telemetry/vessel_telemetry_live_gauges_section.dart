import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_gauge_card.dart';

class VesselTelemetryLiveGaugesSection extends ConsumerWidget {
  final String assetId;

  const VesselTelemetryLiveGaugesSection({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingAsync = ref.watch(latestTelemetryForAssetProvider(assetId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Live Data', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              readingAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (reading) => Text(
                  reading != null
                      ? 'Last updated: ${formatTelemetryTime(reading.ts)}'
                      : '',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        readingAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(friendlyError(context, err),
                style: const TextStyle(color: AppColors.error)),
          ),
          data: (reading) {
            if (reading == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Waiting for data...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  VesselTelemetryGaugeCard(
                    label: 'RPM',
                    value: reading.rpm?.toStringAsFixed(0),
                    unit: '',
                    color: AppColors.primary,
                  ),
                  VesselTelemetryGaugeCard(
                    label: 'Coolant',
                    value: reading.coolantTemp?.toStringAsFixed(1),
                    unit: '°C',
                    color: coolantTelemetryColor(reading.coolantTemp),
                  ),
                  VesselTelemetryGaugeCard(
                    label: 'Oil Pressure',
                    value: reading.oilPressure?.toStringAsFixed(1),
                    unit: 'PSI',
                    color: AppColors.primary,
                  ),
                  VesselTelemetryGaugeCard(
                    label: 'Fuel Rate',
                    value: reading.fuelRate?.toStringAsFixed(2),
                    unit: 'L/hr',
                    color: AppColors.textSecondary,
                  ),
                  VesselTelemetryGaugeCard(
                    label: 'Battery',
                    value: reading.batteryV?.toStringAsFixed(2),
                    unit: 'V',
                    color: batteryTelemetryColor(reading.batteryV),
                  ),
                  VesselTelemetryGaugeCard(
                    label: 'Boost',
                    value: reading.boostPsi?.toStringAsFixed(1),
                    unit: 'PSI',
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
