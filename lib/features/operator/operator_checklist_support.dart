import 'dart:convert';
import 'dart:typed_data';

import 'package:vortice_app/models/checklist_template.dart';

const operatorChecklistDraftKey = 'operator_checklist_draft';
const operatorOfflineSubmitMessage =
    'Checklist could not be submitted right now. Reconnect and try again.';
const operatorPhotoNotSubmittedMessage =
    'Checklist saved, but attached photos stay on this device for now and were not submitted.';
const operatorDefaultRunType = 'pre_departure';

class OperatorChecklistDraftRestoreResult {
  final Map<String, dynamic>? asset;
  final ChecklistTemplate? template;
  final DateTime completedAt;
  final double? currentHours;
  final String? generalNotes;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, Uint8List?> photos;

  const OperatorChecklistDraftRestoreResult({
    required this.asset,
    required this.template,
    required this.completedAt,
    required this.currentHours,
    required this.generalNotes,
    required this.responses,
    required this.notes,
    required this.photos,
  });
}

bool operatorSubmissionHasPhotos(Map<String, Uint8List?> photos) =>
    photos.values.any((photo) => photo != null);

String operatorSubmitSuccessMessage({required bool hasPhotos}) =>
    hasPhotos ? operatorPhotoNotSubmittedMessage : 'Checklist submitted';

Map<String, dynamic> encodeOperatorChecklistDraft({
  required Map<String, dynamic>? asset,
  required ChecklistTemplate? template,
  required Map<String, String?> responses,
  required Map<String, String> notes,
  required DateTime completedAt,
  required double? currentHours,
  required String? generalNotes,
  required Map<String, Uint8List?> photos,
}) {
  return {
    'assetId': asset?['id'] as String?,
    'asset': asset,
    'templateId': template?.id,
    'responses': responses,
    'notes': notes,
    'completedAt': completedAt.toIso8601String(),
    'currentHours': currentHours,
    'generalNotes': generalNotes,
    'photos': photos.map(
      (key, value) => MapEntry(
        key,
        value == null ? null : base64Encode(value),
      ),
    ),
  };
}

OperatorChecklistDraftRestoreResult decodeOperatorChecklistDraft(
  Map<String, dynamic> data, {
  required DateTime fallbackCompletedAt,
  required List<Map<String, dynamic>>? assets,
  required List<ChecklistTemplate> templates,
}) {
  final assetId = data['assetId'] as String?;
  final templateId = data['templateId'] as String?;
  final responses =
      (data['responses'] as Map?)?.cast<String, dynamic>() ?? {};
  final notes = (data['notes'] as Map?)?.cast<String, dynamic>() ?? {};
  final photos = (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};

  var completedAt = fallbackCompletedAt;
  final completedAtRaw = data['completedAt'] as String?;
  if (completedAtRaw != null) {
    completedAt = DateTime.tryParse(completedAtRaw) ?? completedAt;
  }

  var asset = assetId == null
      ? null
      : assets?.where((row) => row['id'] == assetId).firstOrNull;
  final savedAsset = data['asset'];
  if (asset == null && savedAsset is Map) {
    asset = savedAsset.cast<String, dynamic>();
  }

  final template = templateId == null
      ? null
      : templates.where((t) => t.id == templateId).firstOrNull;

  return OperatorChecklistDraftRestoreResult(
    asset: asset,
    template: template,
    completedAt: completedAt,
    currentHours: (data['currentHours'] as num?)?.toDouble(),
    generalNotes: data['generalNotes'] as String?,
    responses: responses.map((key, value) => MapEntry(key, value as String?)),
    notes: notes.map((key, value) => MapEntry(key, value as String)),
    photos: photos.map(
      (key, value) => MapEntry(
        key,
        value is String && value.isNotEmpty ? base64Decode(value) : null,
      ),
    ),
  );
}

Map<String, dynamic>? resolveOperatorInitialAsset({
  required Map<String, dynamic>? currentAsset,
  required String? initialAssetId,
  required List<Map<String, dynamic>>? assets,
}) {
  if (currentAsset != null) return currentAsset;
  if (initialAssetId == null) return null;
  return assets?.where((row) => row['id'] == initialAssetId).firstOrNull;
}

ChecklistTemplate? resolveOperatorInitialTemplate({
  required ChecklistTemplate? currentTemplate,
  required String? initialTemplateId,
  required List<ChecklistTemplate> templates,
}) {
  if (currentTemplate != null) return currentTemplate;
  if (initialTemplateId == null) return null;
  return templates.where((t) => t.id == initialTemplateId).firstOrNull;
}
