import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'field_work_queue.dart';

/// Recovery drafts have their own key so restoring rejected work cannot replace
/// an unrelated unsent draft. Existing corrected input wins over old queue data.
Future<String> restoreSubmissionDraft(
  FieldWorkQueue queue,
  FieldOperation row,
) async {
  queue.checkAccount();
  final prefs = await SharedPreferences.getInstance();
  final suffix = '${row.kind}_recovery_${row.subject}';
  final key = accountStorageKey(queue.account, suffix);
  final data = row.payload['p_data'] as Map;
  final uploads = (row.payload['uploads'] as List).cast<Map>();
  final photos = uploads
      .where((u) => u['bucket'] != 'signatures')
      .map((u) => u['bytes'])
      .toList();
  final signature = uploads
      .where((u) => u['bucket'] == 'signatures')
      .firstOrNull?['bytes'];
  queue.checkAccount();
  Future<void> saveDraft(String key, String value) async {
    queue.checkAccount();
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not retain correction draft');
    }
    queue.checkAccount();
  }

  if (!prefs.containsKey(key)) {
    if (row.kind == 'report_submission') {
      await saveDraft(
        key,
        jsonEncode({
          'workOrderId': data['work_order_id'],
          'pendingReportId': row.subject,
          'complaint': data['complaint'] ?? '',
          'cause': data['cause'] ?? '',
          'correction': data['correction'] ?? '',
          'collateral': data['collateral'] ?? '',
          'comments': data['comments'] ?? '',
          'signatureBytes': signature,
          'photos': photos,
        }),
      );
    } else {
      await saveDraft(
        key,
        jsonEncode({...data, 'id': row.subject, 'photos': photos}),
      );
    }
  }
  queue.checkAccount();
  await queue.archiveSubject(row.subject);
  return suffix;
}
