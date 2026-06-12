import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';

class ServiceIntervalMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const ServiceIntervalMetricChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: AppColors.surfaceVariant,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
