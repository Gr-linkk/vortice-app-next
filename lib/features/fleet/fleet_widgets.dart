import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';

bool fleetSpanish(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'es';
bool fleetFrench(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fr';
String fleetText(BuildContext context, String en, String es, [String? fr]) =>
    Localizations.localeOf(context).languageCode == 'fr'
    ? fr ?? en
    : fleetSpanish(context)
    ? es
    : en;

Color operatingStateColor(AppPalette colors, OperatingState state) =>
    switch (state) {
      OperatingState.available => colors.success,
      OperatingState.restricted => colors.warning,
      OperatingState.outOfService => colors.error,
      OperatingState.underMaintenance => colors.primaryLight,
      OperatingState.unknown => colors.textSecondary,
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
        Localizations.localeOf(context).languageCode,
      ).format(value.toLocal());

String downtimeLabel(Duration duration, {bool french = false}) {
  if (duration.inMinutes < 1) return french ? '<1 min' : '<1 min';
  if (duration.inHours < 1) return '${duration.inMinutes} min';
  if (duration.inDays < 1) {
    return '${duration.inHours} h ${duration.inMinutes % 60} min';
  }
  return '${duration.inDays} ${french ? 'j' : 'd'} ${duration.inHours % 24} h';
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
    label: state.label(fleetSpanish(context), french: fleetFrench(context)),
    color: operatingStateColor(context.appColors, state),
    icon: operatingStateIcon(state),
  );
}

class FaultStatusBadge extends StatelessWidget {
  const FaultStatusBadge({super.key, required this.status});
  final FaultStatus status;
  @override
  Widget build(BuildContext context) => FleetBadge(
    label: status.label(fleetSpanish(context), french: fleetFrench(context)),
    color: status == FaultStatus.resolved
        ? context.appColors.success
        : status == FaultStatus.pendingReview
        ? context.appColors.warning
        : status == FaultStatus.dismissed
        ? context.appColors.textSecondary
        : context.appColors.primaryLight,
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
        Icon(Icons.cloud_off_outlined, color: context.appColors.warning),
        const SizedBox(height: 12),
        Text(
          fleetErrorMessage(
            error,
            fleetSpanish(context),
            french: fleetFrench(context),
          ),
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
        Icon(icon, size: 42, color: context.appColors.primaryLight),
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
          style: TextStyle(color: context.appColors.textSecondary),
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
        ? OperatingState.parse(
            event.toState,
          ).label(es, french: fleetFrench(context))
        : FaultStatus.parse(
            event.toState,
          ).label(es, french: fleetFrench(context));
    final action = switch (event.kind) {
      'work_order_progress' => fleetText(
        context,
        'Work order progress',
        'Avance de la orden',
        'Progression du bon de travail',
      ),
      'reported' => fleetText(
        context,
        'Fault reported',
        'Falla reportada',
        'Défaillance signalée',
      ),
      'assign' => fleetText(
        context,
        'Repair assigned',
        'Responsable asignado',
        'Réparation attribuée',
      ),
      'note' => fleetText(
        context,
        'Progress note',
        'Nota de progreso',
        'Note de suivi',
      ),
      'create_work_order' => fleetText(
        context,
        'Work order linked',
        'Orden de trabajo vinculada',
        'Bon de travail associé',
      ),
      _ => state,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.history,
              size: 18,
              color: context.appColors.primaryLight,
            ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.textSecondary,
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
