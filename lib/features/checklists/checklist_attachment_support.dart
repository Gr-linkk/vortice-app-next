import 'dart:convert';
import 'dart:typed_data';

/// Checklist item photos are stored as lists so gallery + camera can append.
typedef ChecklistItemPhotoLists = Map<String, List<Uint8List>>;
typedef ChecklistItemPhotoUrlLists = Map<String, List<String>>;

List<Uint8List> checklistPhotosForItem(
  ChecklistItemPhotoLists photos,
  String itemId,
) =>
    photos[itemId] ?? const [];

List<String> checklistPhotoUrlsForItem(
  ChecklistItemPhotoUrlLists photoUrls,
  String itemId,
) =>
    photoUrls[itemId] ?? const [];

void appendChecklistPhoto(
  ChecklistItemPhotoLists photos,
  String itemId,
  Uint8List bytes,
) {
  photos.putIfAbsent(itemId, () => []).add(bytes);
}

void removeChecklistPhotoAt(
  ChecklistItemPhotoLists photos,
  String itemId,
  int index,
) {
  final list = photos[itemId];
  if (list == null || index < 0 || index >= list.length) return;
  list.removeAt(index);
  if (list.isEmpty) photos.remove(itemId);
}

void removeChecklistPhotoUrlAt(
  ChecklistItemPhotoUrlLists photoUrls,
  String itemId,
  int index,
) {
  final list = photoUrls[itemId];
  if (list == null || index < 0 || index >= list.length) return;
  list.removeAt(index);
  if (list.isEmpty) photoUrls.remove(itemId);
}

bool checklistItemHasPhotoEvidence({
  required ChecklistItemPhotoLists photos,
  required ChecklistItemPhotoUrlLists photoUrls,
  required String itemId,
}) {
  return checklistPhotosForItem(photos, itemId).isNotEmpty ||
      checklistPhotoUrlsForItem(photoUrls, itemId).isNotEmpty;
}

bool checklistAttachmentsAppendInsteadOfReplace() => true;

String serializeChecklistPhotoUrls(List<String> urls) {
  final cleaned = urls.where((url) => url.trim().isNotEmpty).toList();
  if (cleaned.isEmpty) return '';
  if (cleaned.length == 1) return cleaned.first;
  return jsonEncode(cleaned);
}

List<String> parseChecklistPhotoUrls(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return const [];
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed) as List;
      return decoded.whereType<String>().where((url) => url.isNotEmpty).toList();
    } catch (_) {
      return [trimmed];
    }
  }
  return [trimmed];
}

Map<String, List<String>> encodePhotoListsCache(ChecklistItemPhotoLists photos) {
  final encoded = <String, List<String>>{};
  for (final entry in photos.entries) {
    if (entry.value.isEmpty) continue;
    encoded[entry.key] =
        entry.value.map((bytes) => base64Encode(bytes)).toList(growable: false);
  }
  return encoded;
}

ChecklistItemPhotoLists decodePhotoListsCacheJson(String raw) {
  try {
    final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final decoded = <String, List<Uint8List>>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List) {
        final bytes = value
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .map(base64Decode)
            .toList(growable: false);
        if (bytes.isNotEmpty) decoded[entry.key] = bytes;
      } else if (value is String && value.isNotEmpty) {
        decoded[entry.key] = [base64Decode(value)];
      }
    }
    return decoded;
  } catch (_) {
    return const {};
  }
}

ChecklistItemPhotoUrlLists photoUrlListsFromLegacyMap(
  Map<String, String?> legacy,
) {
  final result = <String, List<String>>{};
  for (final entry in legacy.entries) {
    final urls = parseChecklistPhotoUrls(entry.value);
    if (urls.isNotEmpty) result[entry.key] = urls;
  }
  return result;
}

Map<String, String?> legacyPhotoUrlMapFromLists(
  ChecklistItemPhotoUrlLists photoUrls,
) {
  return {
    for (final entry in photoUrls.entries)
      entry.key: serializeChecklistPhotoUrls(entry.value),
  };
}

ChecklistItemPhotoLists photoListsFromLegacySinglePhotos(
  Map<String, Uint8List?> photos,
) {
  return {
    for (final entry in photos.entries)
      if (entry.value != null) entry.key: [entry.value!],
  };
}
