import 'dart:convert';
import 'dart:typed_data';
import 'field_work_queue.dart';

class FieldEvidencePendingException extends StateError {
  FieldEvidencePendingException({required this.rejected})
    : super('Photo upload is not confirmed');
  final bool rejected;
  String label(bool es, {bool french = false}) => rejected
      ? (french
            ? 'Une photo a été refusée. Le rapport et les photos restent sur cet appareil. Vérifiez vos accès avant de réessayer.'
            : es
            ? 'Una foto fue rechazada. El informe y las fotos permanecen en este dispositivo. Revisa tu acceso antes de reintentar.'
            : 'A photo was rejected. Your report and photos remain on this device. Check your access before retrying.')
      : (french
            ? 'Les photos sont toujours en attente de téléversement. Reconnectez-vous et réessayez; le rapport n’a pas été soumis.'
            : es
            ? 'Las fotos siguen pendientes de subir. Reconecta y reintenta; el informe todavía no se ha enviado.'
            : 'Photos are still waiting to upload. Reconnect and retry; the report has not been submitted.');
}

/// Shared immutable photo contract for internal and provider work. The same
/// path and bytes survive process restarts and uncertain upload responses.
FieldOperation fieldEvidenceOperation({
  required String path,
  required Uint8List bytes,
  String contentType = 'image/jpeg',
}) {
  if (path.startsWith('/') ||
      path.contains('..') ||
      path.split('/').length != 3) {
    throw const FormatException('Invalid evidence path');
  }
  return FieldOperation(
    id: 'photo:$path',
    kind: 'upload',
    subject: path.split('/').first,
    payload: {
      'bucket': 'maintenance-evidence',
      'path': path,
      'bytes': base64Encode(bytes),
      'contentType': contentType,
    },
  );
}

Future<Uint8List?> localFieldEvidence(FieldWorkQueue queue, String path) async {
  final photo = (await queue.list())
      .where(
        (row) =>
            row.kind == 'upload' &&
            row.payload['bucket'] == 'maintenance-evidence' &&
            row.payload['path'] == path,
      )
      .firstOrNull;
  return photo == null ? null : base64Decode(photo.payload['bytes'] as String);
}

/// Publishing a report must never race its durable photo uploads. Queue failures
/// retain the bytes and prevent submission; they are not acknowledgements.
Future<void> requireUploadedFieldEvidence(
  FieldWorkQueue queue,
  Iterable<String> paths,
) async {
  final selected = paths.toSet();
  bool selectedUpload(FieldOperation row) =>
      row.kind == 'upload' &&
      row.payload['bucket'] == 'maintenance-evidence' &&
      selected.contains(row.payload['path']);
  if (!(await queue.list()).any((row) => selectedUpload(row) && !row.synced)) {
    return;
  }
  await queue.restoreEvidence(selected);
  await queue.flush(retryFailed: true);
  final unresolved = (await queue.list()).where(
    (row) => selectedUpload(row) && !row.synced,
  );
  if (unresolved.isNotEmpty) {
    throw FieldEvidencePendingException(
      rejected: unresolved.any((row) => row.needsAttention),
    );
  }
}
