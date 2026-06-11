import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_codec.dart';

class ServiceReportDraftKeys {
  const ServiceReportDraftKeys._();

  static String draftKey(String? initialWorkOrderId) =>
      initialWorkOrderId?.isNotEmpty == true
          ? 'service_report_draft_$initialWorkOrderId'
          : 'service_report_draft';

  static String draftMediaKey(String? initialWorkOrderId) =>
      '${draftKey(initialWorkOrderId)}_media';
}

class ServiceReportDraftData {
  const ServiceReportDraftData({
    this.workOrderId,
    this.pendingReportId,
    this.complaint = '',
    this.cause = '',
    this.correction = '',
    this.collateral = '',
    this.comments = '',
    this.signatureBytes,
    this.photos = const [],
  });

  final String? workOrderId;
  final String? pendingReportId;
  final String complaint;
  final String cause;
  final String correction;
  final String collateral;
  final String comments;
  final List<int>? signatureBytes;
  final List<List<int>> photos;
}

class ServiceReportDraftManager {
  const ServiceReportDraftManager();

  Future<ServiceReportDraftData?> load({
    required String draftKey,
    required String draftMediaKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(draftKey);
    final mediaRaw = prefs.getString(draftMediaKey);
    if (raw == null && mediaRaw == null) return null;

    try {
      final data = raw == null
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();
      final mediaData = mediaRaw == null
          ? data
          : (jsonDecode(mediaRaw) as Map).cast<String, dynamic>();

      List<int>? signatureBytes;
      final signature = mediaData['signatureBytes'];
      if (signature is String && signature.isNotEmpty) {
        signatureBytes = base64Decode(signature);
      }

      final photos = <List<int>>[];
      final photoValues = mediaData['photos'];
      if (photoValues is List) {
        for (final value in photoValues) {
          if (value is String && value.isNotEmpty) {
            photos.add(base64Decode(value));
          }
        }
      }

      return ServiceReportDraftData(
        workOrderId: data['workOrderId'] as String?,
        pendingReportId: data['pendingReportId'] as String?,
        complaint: data['complaint'] as String? ?? '',
        cause: data['cause'] as String? ?? '',
        correction: data['correction'] as String? ?? '',
        collateral: data['collateral'] as String? ?? '',
        comments: data['comments'] as String? ?? '',
        signatureBytes: signatureBytes,
        photos: photos,
      );
    } catch (_) {
      await prefs.remove(draftKey);
      await prefs.remove(draftMediaKey);
      return null;
    }
  }

  Future<void> saveText({
    required String draftKey,
    required String? workOrderId,
    required String? pendingReportId,
    required String complaint,
    required String cause,
    required String correction,
    required String collateral,
    required String comments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hasDraft = ServiceReportDraftCodec.hasTextDraft(
      workOrderId: workOrderId,
      pendingReportId: pendingReportId,
      complaint: complaint,
      cause: cause,
      correction: correction,
      collateral: collateral,
      comments: comments,
    );

    if (!hasDraft) {
      await prefs.remove(draftKey);
      return;
    }

    await prefs.setString(
      draftKey,
      jsonEncode(
        ServiceReportDraftCodec.textPayload(
          workOrderId: workOrderId,
          pendingReportId: pendingReportId,
          complaint: complaint,
          cause: cause,
          correction: correction,
          collateral: collateral,
          comments: comments,
        ),
      ),
    );
  }

  Future<void> saveMedia({
    required String draftMediaKey,
    required List<int>? signatureBytes,
    required List<List<int>> photos,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!ServiceReportDraftCodec.hasMediaDraft(
      signatureBytes == null ? null : Uint8List.fromList(signatureBytes),
      photos.map(Uint8List.fromList).toList(),
    )) {
      await prefs.remove(draftMediaKey);
      return;
    }

    await prefs.setString(
      draftMediaKey,
      jsonEncode(
        ServiceReportDraftCodec.mediaPayload(
          signatureBytes == null ? null : Uint8List.fromList(signatureBytes),
          photos.map(Uint8List.fromList).toList(),
        ),
      ),
    );
  }

  Future<void> clear({
    required String draftKey,
    required String draftMediaKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey);
    await prefs.remove(draftMediaKey);
  }
}
