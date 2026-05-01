import 'package:flutter/foundation.dart';

/// Push notification service stub.
///
/// All notification methods are stubs that log intent via debugPrint.
/// When Firebase is configured (google-services.json + flutterfire configure),
/// replace this with the real FCM implementation.
///
/// Sends notifications to clients when:
/// - Operator flags a maintenance issue on their asset
/// - Pre-trip check has items needing attention
class NotificationService {
  NotificationService._();

  static bool _initialized = false;

  /// Initialize push notification service.
  /// Currently a no-op stub — uncomment Firebase init when configured.
  static Future<void> init() async {
    if (_initialized) return;

    // TODO: Uncomment when Firebase is configured:
    // final messaging = FirebaseMessaging.instance;
    // final settings = await messaging.requestPermission(...);
    // final token = await messaging.getToken();
    // await _saveTokenToProfile(token);

    _initialized = true;
    debugPrint('NotificationService: initialized (stub mode)');
  }

  /// Notify client that an operator flagged a maintenance issue on their asset.
  ///
  /// In production, this calls a Supabase Edge Function that sends
  /// the actual FCM notification to the client's device.
  static Future<void> notifyClientOfMaintenanceFlag({
    required String clientId,
    required String assetName,
    required String issueDescription,
    required String severity,
  }) async {
    debugPrint(
      'STUB: Would notify client $clientId - '
      'Maintenance flag on $assetName: $issueDescription (severity: $severity)',
    );

    // In production, call edge function:
    // await supabase.functions.invoke('send-notification', body: {
    //   'recipient_user_id': clientId,
    //   'title': 'Maintenance Alert: $assetName',
    //   'body': issueDescription,
    //   'data': {'type': 'maintenance_flag', 'severity': severity},
    // });
  }

  /// Notify client of pre-trip check results with flagged items.
  static Future<void> notifyClientOfPreTripFlags({
    required String clientId,
    required String assetName,
    required int flaggedItemCount,
    required String runId,
  }) async {
    debugPrint(
      'STUB: Would notify client $clientId - '
      'Pre-trip check on $assetName has $flaggedItemCount items needing attention',
    );
  }

  /// Notify owner when operator submits a maintenance flag.
  static Future<void> notifyOwnerOfMaintenanceFlag({
    required String assetName,
    required String operatorName,
    required String issueDescription,
    required String severity,
  }) async {
    debugPrint(
      'STUB: Would notify owner - '
      '$operatorName flagged $assetName: $issueDescription (severity: $severity)',
    );
  }
}
