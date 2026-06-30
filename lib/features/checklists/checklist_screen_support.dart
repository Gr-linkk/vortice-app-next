import 'dart:convert';
import 'dart:typed_data';

import 'package:vortice_app/features/checklists/checklist_attachment_support.dart';
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
  final ChecklistItemPhotoLists photos;
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
  final ChecklistItemPhotoUrlLists urls;
  final ChecklistItemPhotoLists remainingPhotos;
  final String? deferredReason;

  const ChecklistPhotoUploadResult({
    required this.urls,
    required this.remainingPhotos,
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
    if (photoUrl?.isNotEmpty == true &&
        !hasPendingLocalChecklistPhoto(response)) {
      photoUrls[itemId] = serializeChecklistPhotoUrls(
        parseChecklistPhotoUrls(photoUrl),
      );
    }
  }

  return SavedChecklistResponseState(
    responses: responses,
    notes: notes,
    photoUrls: photoUrls,
  );
}

ChecklistItemPhotoLists decodePhotoCacheJson(String raw) =>
    decodePhotoListsCacheJson(raw);

Map<String, dynamic> encodePhotoCache(ChecklistItemPhotoLists photos) =>
    encodePhotoListsCache(photos);

ChecklistDraftRestoreResult decodeChecklistDraftJson(
  Map<String, dynamic> data, {
  required DateTime fallbackCompletedAt,
}) {
  final responses = (data['responses'] as Map?)?.cast<String, dynamic>() ?? {};
  final notes = (data['notes'] as Map?)?.cast<String, dynamic>() ?? {};
  final photos = (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};
  final photoUrls = (data['photoUrls'] as Map?)?.cast<String, dynamic>() ?? {};

  var completedAt = fallbackCompletedAt;
  final completedAtRaw = data['completedAt'] as String?;
  if (completedAtRaw != null) {
    completedAt = DateTime.tryParse(completedAtRaw) ?? completedAt;
  }

  final restoredResponses = <String, String?>{};
  final restoredNotes = <String, String>{};
  final restoredPhotoUrls = <String, String?>{};
  final restoredPhotos = <String, List<Uint8List>>{};
  var restoredDraftPhotos = false;

  for (final entry in responses.entries) {
    restoredResponses[entry.key] = entry.value as String?;
  }
  for (final entry in notes.entries) {
    restoredNotes[entry.key] = entry.value as String;
  }
  for (final entry in photoUrls.entries) {
    final localValue = photos[entry.key];
    final hasLocalPhoto = (localValue is List && localValue.isNotEmpty) ||
        (localValue is String && localValue.isNotEmpty);
    if (!hasLocalPhoto) {
      restoredPhotoUrls[entry.key] = entry.value as String?;
    }
  }
  if (photos.isNotEmpty) {
    for (final entry in photos.entries) {
      if (entry.value is List) {
        final encodedParts = (entry.value as List)
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .map(base64Decode)
            .toList(growable: false);
        if (encodedParts.isNotEmpty) {
          restoredPhotos[entry.key] = encodedParts;
          restoredDraftPhotos = true;
        }
      } else if (entry.value is String && (entry.value as String).isNotEmpty) {
        restoredPhotos[entry.key] = [base64Decode(entry.value as String)];
        restoredDraftPhotos = true;
      }
    }
  } else {
    for (final entry in photos.entries) {
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        restoredPhotos[entry.key] = [base64Decode(entry.value as String)];
        restoredDraftPhotos = true;
      }
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
      (boundTemplateId == null || snapshot?.templateId == boundTemplateId)) {
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
  required ChecklistItemPhotoLists photos,
  required ChecklistItemPhotoUrlLists existingUrls,
  required Future<String> Function(String itemId, Uint8List bytes) upload,
}) async {
  String? deferredReason;
  final remainingPhotos = <String, List<Uint8List>>{};
  final urls = {
    for (final entry in existingUrls.entries)
      entry.key: List<String>.from(entry.value),
  };

  for (final entry in photos.entries) {
    final uploaded = <String>[...checklistPhotoUrlsForItem(urls, entry.key)];
    for (final bytes in entry.value) {
      try {
        uploaded.add(await upload(entry.key, bytes));
      } catch (error) {
        deferredReason ??= error.toString();
        remainingPhotos.putIfAbsent(entry.key, () => []).add(bytes);
      }
    }
    if (uploaded.isEmpty) {
      urls.remove(entry.key);
    } else {
      urls[entry.key] = uploaded;
    }
  }

  return ChecklistPhotoUploadResult(
    urls: urls,
    remainingPhotos: remainingPhotos,
    deferredReason: deferredReason,
  );
}

bool hasDeferredChecklistPhotoUpload(String? deferredReason) =>
    deferredReason?.trim().isNotEmpty == true;

Map<String, String?> checklistPhotoUrlsForSubmission(
  ChecklistItemPhotoUrlLists photoUrls,
) =>
    legacyPhotoUrlMapFromLists(photoUrls);

String checklistDraftJson({
  required String? templateId,
  required Map<String, String?> responses,
  required Map<String, String> notes,
  required Map<String, String?> photoUrls,
  required DateTime completedAt,
  required double? currentHours,
  required String? generalNotes,
  required ChecklistItemPhotoLists photos,
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
