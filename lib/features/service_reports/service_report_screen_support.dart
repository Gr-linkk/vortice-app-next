import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';

const serviceReportSubmitFailedMessage =
    'Service report could not be submitted right now. Reconnect and try again.';
const serviceReportSignatureFailedMessage =
    'Signature could not be uploaded right now. Reconnect and try again.';
const serviceReportPhotosPendingMessage =
    'Report saved, but photos are still on this device. Reopen and retry when connected.';

Map<String, dynamic> buildServiceReportPayload({
  required String? selectedWorkOrderId,
  required String complaint,
  required String cause,
  required String correction,
  required String collateral,
  required String comments,
  String? signatureUrl,
}) {
  return {
    'work_order_id':
        selectedWorkOrderId?.isNotEmpty == true ? selectedWorkOrderId : null,
    'complaint': complaint.trim().isNotEmpty ? complaint.trim() : null,
    'cause': cause.trim().isNotEmpty ? cause.trim() : null,
    'correction': correction.trim().isNotEmpty ? correction.trim() : null,
    'collateral': collateral.trim().isNotEmpty ? collateral.trim() : null,
    'comments': comments.trim().isNotEmpty ? comments.trim() : null,
    if (signatureUrl != null) ...{
      'tech_signature_url': signatureUrl,
      'signed_at': DateTime.now().toIso8601String(),
    },
  };
}

Future<String?> uploadServiceReportSignature({
  required Uint8List signatureBytes,
  required String? selectedWorkOrderId,
}) async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final path = '${selectedWorkOrderId}_$ts.png';
  await supabase.storage
      .from(AppConstants.bucketSignatures)
      .uploadBinary(
        path,
        signatureBytes,
        fileOptions: const FileOptions(contentType: 'image/png'),
      )
      .timeout(const Duration(seconds: 4));
  return supabase.storage
      .from(AppConstants.bucketSignatures)
      .getPublicUrl(path);
}

Future<void> updatePendingServiceReport({
  required String reportId,
  required Map<String, dynamic> payload,
}) async {
  await supabase
      .from(AppConstants.tServiceReports)
      .update(payload)
      .eq('id', reportId)
      .timeout(const Duration(seconds: 4));
}

Future<void> uploadServiceReportPhotos({
  required String serviceReportId,
  required List<Uint8List> photos,
}) async {
  for (var i = 0; i < photos.length; i++) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$serviceReportId/${i}_$ts.jpg';
    await supabase.storage
        .from(AppConstants.bucketReportPhotos)
        .uploadBinary(
          path,
          photos[i],
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        )
        .timeout(const Duration(seconds: 4));
    final photoUrl = supabase.storage
        .from(AppConstants.bucketReportPhotos)
        .getPublicUrl(path);
    await supabase.from(AppConstants.tServiceReportPhotos).insert({
      'service_report_id': serviceReportId,
      'photo_url': photoUrl,
      'sort_order': i,
    }).timeout(const Duration(seconds: 4));
  }
}
