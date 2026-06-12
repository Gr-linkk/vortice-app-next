import 'package:flutter/material.dart';
import 'package:vortice_app/models/service_request.dart';

const kServiceRequestOtherAssetValue = '__other_asset__';

bool isOtherAssetSelection(String? assetSelection) =>
    assetSelection == kServiceRequestOtherAssetValue;

double? parseServiceRequestEngineHours(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', ''));
}

String? validateServiceRequestAssetSelection(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please choose an asset or select Other';
  }
  return null;
}

String? validateServiceRequestOtherAssetName(
  String? value, {
  required bool isOtherAsset,
}) {
  if (isOtherAsset && (value == null || value.trim().isEmpty)) {
    return 'Please describe the asset';
  }
  return null;
}

String? validateServiceRequestEngineHours(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = parseServiceRequestEngineHours(text);
  if (parsed == null || parsed < 0) {
    return 'Enter valid engine hours';
  }
  return null;
}

String? validateServiceRequestDescription(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please describe the issue';
  }
  return null;
}

String? validateServiceRequestContact(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please provide a phone number or WhatsApp';
  }
  return null;
}

String? resolveServiceRequestAssetId(String? assetSelection) {
  if (isOtherAssetSelection(assetSelection)) return null;
  return assetSelection;
}

String? resolveServiceRequestOtherAssetName(
  String? assetSelection,
  String otherAssetName,
) {
  if (!isOtherAssetSelection(assetSelection)) return null;
  final trimmed = otherAssetName.trim();
  return trimmed.isEmpty ? null : trimmed;
}

IconData serviceRequestKindIcon(ServiceRequestKind kind) => switch (kind) {
      ServiceRequestKind.breakdown => Icons.warning_amber_outlined,
      ServiceRequestKind.serviceMaintenance => Icons.build_outlined,
      ServiceRequestKind.safetyConcern => Icons.health_and_safety_outlined,
      ServiceRequestKind.otherIssue => Icons.more_horiz,
    };
