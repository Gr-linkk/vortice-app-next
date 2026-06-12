import 'dart:convert';
import 'dart:typed_data';

import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

class ChecklistDraftRestoreResult {
  final String? templateId;
  final DateTime completedAt;
  final double? currentHours;
  final String? generalNotes;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, String?> photoUrls;
  final Map<String, Uint8List?> photos;
  final bool restoredDraftPhotos;

  const ChecklistDraftRestoreResult({
    required this.templateId,
    required this.completedAt,
    required this.currentHours,
    required this.generalNotes,
    required this.responses,
    required this.notes,
    required this.photoUrls,
    required this.photos,
    required this.restoredDraftPhotos,
  });
}

class ChecklistTemplateSelection {
  final ChecklistTemplate? selected;
  final String? draftTemplateId;
  final bool showPicker;

  const ChecklistTemplateSelection({
    required this.selected,
    required this.draftTemplateId,
    required this.showPicker,
  });
}

class ChecklistPhotoUploadResult {
  final Map<String, String?> urls;
  final String? deferredReason;

  const ChecklistPhotoUploadResult({
    required this.urls,
    required this.deferredReason,
  });
}

class SavedChecklistResponseState {
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, String?> photoUrls;

  const SavedChecklistResponseState({
    required this.responses,
    required this.notes,
    required this.photoUrls,
  });
}

bool hasPendingLocalChecklistPhoto(ChecklistResponse response) =>
    response.syncStatus != SyncStatusValues.synced &&
    response.lastError != null &&
    response.lastError!.isNotEmpty;

String? responseStatusFromSaved(ChecklistResponse response) =>
    response.responseStatus ?? (response.completed ? 'pass' : 'monitor');

SavedChecklistResponseState savedResponsesFromWorkOrder(
  Iterable<ChecklistResponse> savedResponses,
) {
  final responses = <String, String?>{};
  final notes = <String, String>{};
  final photoUrls = <String, String?>{};

  for (final response in savedResponses) {
    final itemId = response.checklistItemId;
    responses[itemId] = responseStatusFromSaved(response);
    final note = response.notes;
    if (note?.isNotEmpty == true) {
      notes[itemId] = note!;
    }
    final photoUrl = response.photoUrl;
    if (photoUrl?.isNotEmpty == true && !hasPendingLocalChecklistPhoto(response)) {
      photoUrls[itemId] = photoUrl;
    }
  }

  return SavedChecklistResponseState(
    responses: responses,
    notes: notes,
    photoUrls: photoUrls,
  );
}

Map<String, Uint8List> decodePhotoCacheJson(String raw) {
  try {
    final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final decoded = <String, Uint8List>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        decoded[entry.key] = base64Decode(value);
      }
    }
    return decoded;
  } catch (_) {
    return const {};
  }
}

Map<String, String> encodePhotoCache(Map<String, Uint8List?> photos) {
  final encoded = <String, String>{};
  for (final entry in photos.entries) {
    final bytes = entry.value;
    if (bytes != null) {
      encoded[entry.key] = base64Encode(bytes);
    }
  }
  return encoded;
}

ChecklistDraftRestoreResult decodeChecklistDraftJson(
  Map<String, dynamic> data, {
  required DateTime fallbackCompletedAt,
}) {
  final responses =
      (data['responses'] as Map?)?.cast<String, dynamic>() ?? {};
  final notes = (data['notes'] as Map?)?.cast<String, dynamic>() ?? {};
  final photos = (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};
  final photoUrls =
      (data['photoUrls'] as Map?)?.cast<String, dynamic>() ?? {};

  var completedAt = fallbackCompletedAt;
  final completedAtRaw = data['completedAt'] as String?;
  if (completedAtRaw != null) {
    completedAt = DateTime.tryParse(completedAtRaw) ?? completedAt;
  }

  final restoredResponses = <String, String?>{};
  final restoredNotes = <String, String>{};
  final restoredPhotoUrls = <String, String?>{};
  final restoredPhotos = <String, Uint8List?>{};
  var restoredDraftPhotos = false;

  for (final entry in responses.entries) {
    restoredResponses[entry.key] = entry.value as String?;
  }
  for (final entry in notes.entries) {
    restoredNotes[entry.key] = entry.value as String;
  }
  for (final entry in photoUrls.entries) {
    final hasLocalPhoto =
        photos[entry.key] is String && (photos[entry.key] as String).isNotEmpty;
    if (!hasLocalPhoto) {
      restoredPhotoUrls[entry.key] = entry.value as String?;
    }
  }
  for (final entry in photos.entries) {
    if (entry.value is String && (entry.value as String).isNotEmpty) {
      restoredPhotos[entry.key] = base64Decode(entry.value as String);
      restoredDraftPhotos = true;
    }
  }

  return ChecklistDraftRestoreResult(
    templateId: data['templateId'] as String?,
    completedAt: completedAt,
    currentHours: (data['currentHours'] as num?)?.toDouble(),
    generalNotes: data['generalNotes'] as String?,
    responses: restoredResponses,
    notes: restoredNotes,
    photoUrls: restoredPhotoUrls,
    photos: restoredPhotos,
    restoredDraftPhotos: restoredDraftPhotos,
  );
}

ChecklistTemplateSelection resolveChecklistTemplateSelection({
  required ChecklistTemplate? currentSelected,
  required String? currentDraftTemplateId,
  required bool currentShowPicker,
  required WorkOrderChecklistSnapshot? snapshot,
  required String? boundTemplateId,
  required List<ChecklistTemplate> templates,
}) {
  var selected = currentSelected;
  var draftTemplateId = currentDraftTemplateId;
  var showPicker = currentShowPicker;
  final snapshotTemplate = snapshot?.asTemplate();

  if (snapshotTemplate != null &&
      (boundTemplateId == null ||
          snapshot?.templateId == boundTemplateId)) {
    selected = snapshotTemplate;
    draftTemplateId = snapshot?.templateId ?? draftTemplateId;
    showPicker = false;
  } else if (selected == null && boundTemplateId != null) {
    final matches = templates.where((t) => t.id == boundTemplateId);
    if (matches.isNotEmpty) {
      selected = matches.first;
      draftTemplateId = matches.first.id;
      showPicker = false;
    }
  } else if (selected == null && draftTemplateId != null) {
    final matches = templates.where((t) => t.id == draftTemplateId);
    if (matches.isNotEmpty) {
      selected = matches.first;
      showPicker = false;
    }
  }

  return ChecklistTemplateSelection(
    selected: selected,
    draftTemplateId: draftTemplateId,
    showPicker: showPicker,
  );
}

bool shouldShowChecklistTemplatePicker({
  required bool templateSelectionLocked,
  required bool showPicker,
  required ChecklistTemplate? selectedTemplate,
}) =>
    !templateSelectionLocked && (showPicker || selectedTemplate == null);

List<ChecklistItem>? snapshotItemsForTemplate({
  required WorkOrderChecklistSnapshot? snapshot,
  required ChecklistTemplate selectedTemplate,
}) {
  if (snapshot == null || snapshot.items.isEmpty) return null;
  if (snapshot.templateId == selectedTemplate.id ||
      snapshot.asTemplate().id == selectedTemplate.id) {
    return snapshot.items;
  }
  return null;
}

String? buildChecklistMetadataCaption({
  required WorkOrderChecklistSnapshot? snapshot,
  required List<ChecklistItem>? snapshotItems,
}) {
  final metaBits = <String>[];
  if (snapshot?.intervalLabel?.trim().isNotEmpty == true) {
    metaBits.add(snapshot!.intervalLabel!.trim());
  }
  if ((snapshot?.intervalHours ?? 0) > 0) {
    metaBits.add('${snapshot!.intervalHours}h');
  }
  if ((snapshot?.templateVersion ?? 0) > 0) {
    metaBits.add('v${snapshot!.templateVersion}');
  }
  if (snapshotItems != null) {
    metaBits.add('${snapshotItems.length} items');
  }
  return metaBits.isEmpty ? null : metaBits.join(' • ');
}

Future<ChecklistPhotoUploadResult> uploadPendingChecklistPhotos({
  required Map<String, Uint8List?> photos,
  required Map<String, String?> existingUrls,
  required Future<String> Function(String itemId, Uint8List bytes) upload,
}) async {
  String? deferredReason;
  final urls = Map<String, String?>.from(existingUrls);

  for (final entry in photos.entries) {
    final bytes = entry.value;
    if (bytes == null) {
      urls[entry.key] = null;
      continue;
    }

    final existingUrl = urls[entry.key];
    try {
      urls[entry.key] = await upload(entry.key, bytes);
    } catch (error) {
      deferredReason ??= error.toString();
      urls[entry.key] = existingUrl;
    }
  }

  return ChecklistPhotoUploadResult(urls: urls, deferredReason: deferredReason);
}

String checklistDraftJson({
  required String? templateId,
  required Map<String, String?> responses,
  required Map<String, String> notes,
  required Map<String, String?> photoUrls,
  required DateTime completedAt,
  required double? currentHours,
  required String? generalNotes,
  required Map<String, Uint8List?> photos,
}) =>
    jsonEncode(
      encodeChecklistDraft(
        templateId: templateId,
        responses: responses,
        notes: notes,
        photoUrls: photoUrls,
        completedAt: completedAt,
        currentHours: currentHours,
        generalNotes: generalNotes,
        photos: photos,
      ),
    );
