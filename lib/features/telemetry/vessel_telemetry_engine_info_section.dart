import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset_engine.dart';

class VesselTelemetryEngineInfoSection extends StatelessWidget {
  final AssetEngine engine;

  const VesselTelemetryEngineInfoSection({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('Engine Data',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(
                  BorderSide(color: AppColors.cardBorder)),
            ),
            child: Column(
              children: [
                VesselTelemetryInfoRow(label: 'Label', value: engine.label),
                if (engine.make != null)
                  VesselTelemetryInfoRow(label: 'Make', value: engine.make!),
                if (engine.model != null)
                  VesselTelemetryInfoRow(label: 'Model', value: engine.model!),
                if (engine.serialNumber != null)
                  VesselTelemetryInfoRow(
                      label: 'Serial', value: engine.serialNumber!),
                VesselTelemetryInfoRow(
                  label: 'Engine Hours',
                  value: engine.currentHours.toStringAsFixed(1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class VesselTelemetryInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const VesselTelemetryInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
