import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class TelemetryDetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const TelemetryDetailRow({
    super.key,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value!,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
