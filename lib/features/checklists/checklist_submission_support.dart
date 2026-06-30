import 'dart:async';
import 'dart:io';

/// Distinguishes intentional offline queueing from online validation failures.
class ChecklistSubmissionSupport {
  const ChecklistSubmissionSupport._();

  static bool isTransientSyncError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is IOException) return true;

    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('network is unreachable') ||
        message.contains('connection timed out') ||
        message.contains('timeoutexception');
  }

  static bool isPermissionSyncError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('row-level security') ||
        message.contains('42501') ||
        message.contains('forbidden') ||
        message.contains('permission denied');
  }

  static String onlineSubmittedMessage({String? deferredPhotoReason}) {
    if (deferredPhotoReason == null || deferredPhotoReason.trim().isEmpty) {
      return 'Checklist submitted.';
    }
    return 'Checklist submitted. Some photos will sync when connection improves.';
  }

  static String pendingSyncMessage({required bool intentionalOffline}) {
    return intentionalOffline
        ? 'Saved locally while offline. Sync pending.'
        : 'Saved locally. Sync pending.';
  }
}
