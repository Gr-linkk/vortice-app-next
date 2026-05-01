import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';

class ReminderScreen extends ConsumerWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final remindersAsync = ref.watch(remindersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.upcomingServices)),
      body: remindersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(err.toString()),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(remindersProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (reminders) {
          if (reminders.isEmpty) {
            return Center(
              child: Text(l10n.noReminders,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          // Group by urgency
          final overdue =
              reminders.where((r) => r.urgency == 'overdue').toList();
          final dueSoon =
              reminders.where((r) => r.urgency == 'dueSoon').toList();
          final upcoming =
              reminders.where((r) => r.urgency == 'upcoming').toList();
          final later =
              reminders.where((r) => r.urgency == 'later').toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(remindersProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (overdue.isNotEmpty)
                  _ReminderSection(
                    title: l10n.overdue,
                    color: AppColors.error,
                    reminders: overdue,
                  ),
                if (dueSoon.isNotEmpty)
                  _ReminderSection(
                    title: l10n.dueSoon,
                    color: AppColors.warning,
                    reminders: dueSoon,
                  ),
                if (upcoming.isNotEmpty)
                  _ReminderSection(
                    title: l10n.upcomingLabel,
                    color: const Color(0xFFFDD835),
                    reminders: upcoming,
                  ),
                if (later.isNotEmpty)
                  _ReminderSection(
                    title: l10n.laterLabel,
                    color: AppColors.textSecondary,
                    reminders: later,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReminderSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<ReminderWithAsset> reminders;

  const _ReminderSection({
    required this.title,
    required this.color,
    required this.reminders,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        ...reminders.map((r) => _ReminderCard(reminder: r, color: color)),
      ],
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  final ReminderWithAsset reminder;
  final Color color;

  const _ReminderCard({required this.reminder, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hoursRemaining = reminder.hoursRemaining;
    final progress = reminder.reminder.dueAtHours > 0
        ? (reminder.currentHours / reminder.reminder.dueAtHours).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _confirmAcknowledge(context, ref, l10n),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(reminder.assetName,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Text(
                    '${reminder.reminder.intervalHours}HR Service',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.surfaceVariant,
                  color: color,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${reminder.currentHours.toStringAsFixed(1)} hrs',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                  Text(
                    '${l10n.dueAt} ${reminder.reminder.dueAtHours.toStringAsFixed(1)} hrs',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hoursRemaining <= 0
                    ? '${hoursRemaining.abs().toStringAsFixed(1)} hrs ${l10n.overdue.toLowerCase()}'
                    : '${hoursRemaining.toStringAsFixed(1)} hrs ${l10n.remaining}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (reminder.checklistTemplateId != null) ...[
                const SizedBox(height: 8),
                _ReadinessBadge(templateId: reminder.checklistTemplateId!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAcknowledge(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.acknowledgeReminder),
        content: Text(l10n.acknowledgeReminderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(reminderControllerProvider.notifier)
          .acknowledgeReminder(reminder.reminder.id);
    }
  }
}

// ── Readiness badge ─────────────────────────────────────────────────────────

class _ReadinessBadge extends ConsumerWidget {
  final String templateId;

  const _ReadinessBadge({required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readinessAsync = ref.watch(pmReadinessProvider(templateId));

    return readinessAsync.when(
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (readiness) {
        final Color chipColor;
        final String chipLabel;

        switch (readiness.level) {
          case ReadinessLevel.ready:
            chipColor = AppColors.success;
            chipLabel = l10n.partsReady;
          case ReadinessLevel.partial:
            chipColor = AppColors.warning;
            chipLabel =
                '${l10n.partsPartial} (${l10n.partsMissing(readiness.missingParts.length)})';
          case ReadinessLevel.notReady:
            chipColor = AppColors.error;
            chipLabel = l10n.partsNotReady;
        }

        return Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: chipColor.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    readiness.level == ReadinessLevel.ready
                        ? Icons.check_circle_outline
                        : readiness.level == ReadinessLevel.partial
                            ? Icons.warning_amber_outlined
                            : Icons.cancel_outlined,
                    color: chipColor,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    chipLabel,
                    style: TextStyle(
                      color: chipColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
