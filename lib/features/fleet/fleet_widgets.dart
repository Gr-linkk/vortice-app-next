import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';

bool fleetSpanish(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'es';
String fleetText(BuildContext context, String en, String es) =>
    fleetSpanish(context) ? es : en;

Color operatingStateColor(OperatingState state) => switch (state) {
  OperatingState.available => AppColors.success,
  OperatingState.restricted => AppColors.warning,
  OperatingState.outOfService => AppColors.error,
  OperatingState.underMaintenance => AppColors.primaryLight,
  OperatingState.unknown => AppColors.textSecondary,
};
IconData operatingStateIcon(OperatingState state) => switch (state) {
  OperatingState.available => Icons.check_circle_outline,
  OperatingState.restricted => Icons.warning_amber_rounded,
  OperatingState.outOfService => Icons.do_not_disturb_on_outlined,
  OperatingState.underMaintenance => Icons.build_outlined,
  OperatingState.unknown => Icons.help_outline,
};

String fleetDate(BuildContext context, DateTime? value) => value == null
    ? '—'
    : DateFormat(
        'MMM d, HH:mm',
        fleetSpanish(context) ? 'es' : 'en',
      ).format(value.toLocal());

String downtimeLabel(Duration duration) {
  if (duration.inMinutes < 1) return '<1 min';
  if (duration.inHours < 1) return '${duration.inMinutes} min';
  if (duration.inDays < 1) {
    return '${duration.inHours} h ${duration.inMinutes % 60} min';
  }
  return '${duration.inDays} d ${duration.inHours % 24} h';
}

class FleetBadge extends StatelessWidget {
  const FleetBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class OperatingStateBadge extends StatelessWidget {
  const OperatingStateBadge({super.key, required this.state});
  final OperatingState state;
  @override
  Widget build(BuildContext context) => FleetBadge(
    label: state.label(fleetSpanish(context)),
    color: operatingStateColor(state),
    icon: operatingStateIcon(state),
  );
}

class FaultStatusBadge extends StatelessWidget {
  const FaultStatusBadge({super.key, required this.status});
  final FaultStatus status;
  @override
  Widget build(BuildContext context) => FleetBadge(
    label: status.label(fleetSpanish(context)),
    color: status == FaultStatus.resolved
        ? AppColors.success
        : status == FaultStatus.pendingReview
        ? AppColors.warning
        : status == FaultStatus.dismissed
        ? AppColors.textSecondary
        : AppColors.primaryLight,
  );
}

class FleetError extends StatelessWidget {
  const FleetError({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
        const SizedBox(height: 12),
        Text(
          fleetErrorMessage(error, fleetSpanish(context)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(fleetText(context, 'Retry', 'Reintentar')),
        ),
      ],
    ),
  );
}

class FleetEmpty extends StatelessWidget {
  const FleetEmpty({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.task_alt,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: AppColors.primaryLight),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class FleetEventTile extends StatelessWidget {
  const FleetEventTile({
    super.key,
    required this.event,
    this.availability = false,
  });
  final FleetEvent event;
  final bool availability;
  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    final state = availability
        ? OperatingState.parse(event.toState).label(es)
        : FaultStatus.parse(event.toState).label(es);
    final action = switch (event.kind) {
      'reported' => es ? 'Falla reportada' : 'Fault reported',
      'assign' => es ? 'Responsable asignado' : 'Repair assigned',
      'note' => es ? 'Nota de progreso' : 'Progress note',
      'create_work_order' =>
        es ? 'Orden de trabajo vinculada' : 'Work order linked',
      _ => state,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.history, size: 18, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(event.note),
                const SizedBox(height: 6),
                Text(
                  '${event.actorName} · ${fleetDate(context, event.createdAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
