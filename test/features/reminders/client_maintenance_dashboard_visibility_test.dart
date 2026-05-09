import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/models/service_reminder.dart';

ReminderWithAsset _reminder({
  required double currentHours,
  required double dueAtHours,
}) {
  return ReminderWithAsset(
    reminder: ServiceReminder(
      id: 'reminder-$dueAtHours',
      assetId: 'asset-1',
      intervalHours: 250,
      dueAtHours: dueAtHours,
    ),
    assetName: 'Ellicott 460SL',
    currentHours: currentHours,
  );
}

void main() {
  test('client maintenance dashboard hides far-future planned intervals', () {
    final farFuture = _reminder(currentHours: 0, dueAtHours: 250);
    final upcoming = _reminder(currentHours: 205, dueAtHours: 250);
    final dueSoon = _reminder(currentHours: 245, dueAtHours: 250);
    final overdue = _reminder(currentHours: 260, dueAtHours: 250);

    expect(farFuture.urgency, 'later');
    expect(farFuture.shouldShowOnClientMaintenanceDashboard, isFalse);

    expect(upcoming.urgency, 'upcoming');
    expect(upcoming.shouldShowOnClientMaintenanceDashboard, isTrue);
    expect(dueSoon.urgency, 'dueSoon');
    expect(dueSoon.shouldShowOnClientMaintenanceDashboard, isTrue);
    expect(overdue.urgency, 'overdue');
    expect(overdue.shouldShowOnClientMaintenanceDashboard, isTrue);
  });
}
