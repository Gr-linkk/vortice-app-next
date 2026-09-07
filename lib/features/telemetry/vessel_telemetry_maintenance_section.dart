import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_screen_support.dart';

class VesselTelemetryMaintenanceSection extends ConsumerWidget {
  final String assetId;

  const VesselTelemetryMaintenanceSection({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersProvider);

    return remindersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (reminders) {
        final assetReminders = reminders
            .where((r) => r.reminder.assetId == assetId)
            .toList();

        if (assetReminders.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Maintenance Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...assetReminders
                .take(5)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.appColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.fromBorderSide(
                          BorderSide(color: context.appColors.cardBorder),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: context.appColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${r.reminder.intervalHours} hr service',
                              style: TextStyle(
                                color: context.appColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            maintenanceHoursRemainingLabel(r.hoursRemaining),
                            style: TextStyle(
                              color: maintenanceHoursRemainingColor(
                                context.appColors,
                                r.hoursRemaining,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
