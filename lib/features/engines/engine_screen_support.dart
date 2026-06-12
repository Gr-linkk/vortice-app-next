import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';

Color engineKindColor(String kind) => switch (kind) {
      'main' || 'port' || 'starboard' || 'wing' => AppColors.primary,
      'generator' => AppColors.success,
      'auxiliary' => AppColors.warning,
      _ => AppColors.textSecondary,
    };

String displayEngineInfoValue(String? value) {
  return value?.trim().isNotEmpty == true ? value! : '—';
}

String formatLatestEngineHoursSubtitle(double? latestHours) {
  return latestHours != null
      ? '${latestHours.toStringAsFixed(1)} hrs · latest WO'
      : 'No work order hours yet';
}

String formatLatestEngineHoursDetail(double? hours) {
  return hours != null ? '${hours.toStringAsFixed(1)} hrs' : '—';
}

String? trimToNull(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic> buildEngineFormPayload({
  required String assetId,
  required String kind,
  required String make,
  required String model,
  required String serialNumber,
}) {
  return {
    'asset_id': assetId,
    'label': suggestedEngineLabel(kind),
    'kind': normalizeEngineKind(kind),
    'make': trimToNull(make),
    'model': trimToNull(model),
    'serial_number': trimToNull(serialNumber),
  };
}
