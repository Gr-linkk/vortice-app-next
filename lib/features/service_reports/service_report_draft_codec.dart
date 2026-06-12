import 'dart:convert';
import 'dart:typed_data';

class ServiceReportDraftCodec {
  const ServiceReportDraftCodec._();

  static bool hasTextDraft({
    required String? workOrderId,
    required String? pendingReportId,
    required String complaint,
    required String cause,
    required String correction,
    required String collateral,
    required String comments,
  }) {
    return workOrderId != null ||
        pendingReportId != null ||
        complaint.trim().isNotEmpty ||
        cause.trim().isNotEmpty ||
        correction.trim().isNotEmpty ||
        collateral.trim().isNotEmpty ||
        comments.trim().isNotEmpty;
  }

  static Map<String, dynamic> textPayload({
    required String? workOrderId,
    required String? pendingReportId,
    required String complaint,
    required String cause,
    required String correction,
    required String collateral,
    required String comments,
  }) {
    return {
      'workOrderId': workOrderId,
      'pendingReportId': pendingReportId,
      'complaint': complaint,
      'cause': cause,
      'correction': correction,
      'collateral': collateral,
      'comments': comments,
    };
  }

  static bool hasMediaDraft(Uint8List? signatureBytes, List<Uint8List> photos) {
    return signatureBytes != null || photos.isNotEmpty;
  }

  static Map<String, dynamic> mediaPayload(
    Uint8List? signatureBytes,
    List<Uint8List> photos,
  ) {
    return {
      'signatureBytes':
          signatureBytes == null ? null : base64Encode(signatureBytes),
      'photos': photos.map(base64Encode).toList(),
    };
  }
}
