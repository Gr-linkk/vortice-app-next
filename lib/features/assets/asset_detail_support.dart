import 'package:intl/intl.dart';
import 'package:vortice_app/features/assets/asset_workflow_summary.dart';

String formatAssetChecklistSummaryValue(AssetChecklistSummary? checklist) {
  if (checklist == null) return 'None saved yet';
  return '${checklist.name} • ${DateFormat('MMM d, yyyy').format(checklist.submittedAt.toLocal())}';
}

String formatAssetPmDueSummaryValue(AssetPmDueSummary summary) {
  final count = summary.dueOrOverdueCount;
  if (count == 0) return 'Nothing due';
  final suffix = count == 1 ? 'interval' : 'intervals';
  final labels = summary.labels.take(2).join(', ');
  final more = count > 2 ? ' +${count - 2} more' : '';
  return '$count $suffix • $labels$more';
}

String formatDeviceMinutesAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  return '${diff.inMinutes}m ago';
}

String formatDeviceRelativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
