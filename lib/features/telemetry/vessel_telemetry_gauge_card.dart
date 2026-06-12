import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class VesselTelemetryGaugeCard extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;
  final Color color;

  const VesselTelemetryGaugeCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value ?? '—',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            height: 3,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
