import 'dashboard_work.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/features/coordination/fleet_overview_screen.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/sign_out_button.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/fleet/fleet_entry_card.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';

String dashboardText(
  BuildContext context,
  String en,
  String es, [
  String? fr,
]) => localizedText(context, en, es, fr ?? en);

class DashboardRefresh extends ConsumerWidget {
  const DashboardRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(fleetAssetsProvider);
      ref.invalidate(fleetAttentionProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(maintenanceJobsProvider);
      ref.invalidate(workListProvider);
      await onRefresh();
      try {
        await ref.read(fleetAssetsProvider.future);
      } catch (_) {
        // The fleet card keeps its recoverable error state.
      }
    },
    child: child,
  );
}

/// Every profile uses the same home landmarks; destinations retain role access.
class DashboardAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const DashboardAppBar({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).valueOrNull?.role;
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(dashboardText(context, 'Home', 'Inicio', 'Accueil')),
      actions: [
        if (role != null)
          const _DashboardNotifications(route: '/notifications'),
        const SignOutButton(),
      ],
    );
  }
}

class _DashboardNotifications extends ConsumerWidget {
  const _DashboardNotifications({required this.route});
  final String route;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: dashboardText(
        context,
        'Notifications',
        'Notificaciones',
        'Notifications',
      ),
      onPressed: () => context.push(route),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class DashboardList extends ConsumerWidget {
  const DashboardList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCurrent = [
      UserRole.employee,
      UserRole.clientMechanic,
    ].contains(ref.watch(profileProvider).valueOrNull?.role);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 950 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.8;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            wide ? 24 : 0,
            wide ? 16 : 0,
            wide ? 24 : 0,
            32,
          ),
          children: [
            const DashboardIntro(),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showCurrent) const DashboardCurrentWork(),
                        ...children,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  const Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DashboardPriorities(),
                        FleetEntryCard(),
                        DashboardShortcuts(),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              const DashboardPriorities(),
              const FleetEntryCard(),
              if (showCurrent) const DashboardCurrentWork(),
              ...children,
              const DashboardShortcuts(),
            ],
          ],
        );
      },
    );
  }
}

class DashboardIntro extends ConsumerWidget {
  const DashboardIntro({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.client;
    final name = profile?.fullName.trim().split(' ').first ?? '';
    final es = Localizations.localeOf(context).languageCode == 'es';
    final fr = isFrench(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty
                    ? localizedText(
                        context,
                        'Welcome back',
                        'Bienvenido',
                        'Bon retour',
                      )
                    : localizedText(
                        context,
                        'Hi, $name',
                        'Hola, $name',
                        'Bonjour, $name',
                      ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '${dashboardRoleLabel(role, es, french: fr)} · ${DateFormat.MMMEd(appLocaleCode(context)).format(DateTime.now())}',
                style: TextStyle(color: context.appColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DashboardPriorities extends ConsumerWidget {
  const DashboardPriorities({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).valueOrNull?.role;
    return canManageFleet(role)
        ? const FleetPriorityCard()
        : const SizedBox.shrink();
  }
}

class DashboardShortcuts extends ConsumerWidget {
  const DashboardShortcuts({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role =
        ref.watch(profileProvider).valueOrNull?.role ?? UserRole.client;
    final es = isSpanish(context);
    final operator =
        role == UserRole.operator || role == UserRole.clientOperator;
    final checks =
        operator &&
        (ref
                .watch(
                  clientCapabilityGateProvider((
                    clientId: null,
                    capability: ClientCapability.operationalChecklists,
                  )),
                )
                .valueOrNull ??
            false);
    final actions = dashboardActions(
      role,
      operationalChecklistsEnabled: checks,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardSection(
          title: localizedText(context, 'Tools', 'Herramientas', 'Outils'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final action in actions)
                  ListTile(
                    leading: Icon(
                      action.icon,
                      color: context.appColors.primary,
                    ),
                    title: Text(action.label(es, french: isFrench(context))),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => context.push(action.route),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<AppDestination> dashboardActions(
  UserRole role, {
  bool operationalChecklistsEnabled = false,
}) {
  final prefix = roleRoutePrefix(role);
  final staff = role == UserRole.owner || role == UserRole.employee;
  final admin = role == UserRole.client || role == UserRole.clientAdmin;
  return [
    if (staff || admin || role == UserRole.clientMechanic)
      AppDestination(
        'Work orders',
        'Órdenes de trabajo',
        Icons.calendar_month_outlined,
        role == UserRole.owner || admin
            ? '/maintenance/planning'
            : '/maintenance/planning?filter=mine',
        fr: 'Bons de travail',
      ),
    const AppDestination(
      'Report a fault',
      'Reportar una falla',
      Icons.report_problem_outlined,
      '/fleet/report',
      fr: 'Signaler une défaillance',
    ),
    if (role == UserRole.owner || admin)
      const AppDestination(
        'New work order',
        'Nueva orden de trabajo',
        Icons.add_task,
        '/maintenance/new',
        fr: 'Créer un bon de travail',
      )
    else if (operationalChecklistsEnabled &&
        (role == UserRole.operator || role == UserRole.clientOperator))
      const AppDestination(
        'Start checklist',
        'Iniciar revisión',
        Icons.checklist,
        '/operator/checklist',
        fr: 'Commencer une inspection',
      )
    else if (!staff && role != UserRole.clientMechanic)
      AppDestination(
        'View assets',
        'Ver equipos',
        Icons.directions_boat_outlined,
        '$prefix/assets',
        fr: 'Voir les équipements',
      ),
    if (staff)
      AppDestination(
        'Service requests',
        'Solicitudes de servicio',
        Icons.support_agent,
        '$prefix/service-requests',
        fr: 'Demandes de service',
      )
    else if (admin || role == UserRole.clientMechanic)
      const AppDestination(
        'Service reports',
        'Informes de servicio',
        Icons.description_outlined,
        '/client/service-reports',
        fr: 'Rapports d’intervention',
      )
    else if (operationalChecklistsEnabled)
      AppDestination(
        'View assets',
        'Ver equipos',
        Icons.directions_boat_outlined,
        '$prefix/assets',
        fr: 'Voir les équipements',
      )
    else
      const AppDestination(
        'Notifications',
        'Notificaciones',
        Icons.notifications_outlined,
        '/notifications',
        fr: 'Notifications',
      ),
    const AppDestination(
      'All tools',
      'Todas las herramientas',
      Icons.grid_view_outlined,
      '/more',
      fr: 'Tous les outils',
    ),
  ];
}

String dashboardRoleLabel(UserRole role, bool es, {bool french = false}) =>
    switch (role) {
      UserRole.owner =>
        french
            ? 'Administration'
            : es
            ? 'Administración'
            : 'Administration',
      UserRole.employee =>
        french
            ? 'Équipe de service'
            : es
            ? 'Equipo de servicio'
            : 'Service team',
      UserRole.client || UserRole.clientAdmin =>
        french
            ? 'Mon entreprise'
            : es
            ? 'Mi empresa'
            : 'My company',
      UserRole.clientMechanic =>
        french
            ? 'Mécanicien'
            : es
            ? 'Mecánico'
            : 'Mechanic',
      UserRole.operator || UserRole.clientOperator =>
        french
            ? 'Opérateur'
            : es
            ? 'Operador'
            : 'Operator',
    };

class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    this.color,
    this.inset = true,
    this.onViewAll,
  });
  final String title;
  final Color? color;
  final bool inset;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context) => Padding(
    padding: inset ? const EdgeInsets.fromLTRB(16, 24, 16, 8) : EdgeInsets.zero,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Text(
              dashboardText(context, 'View all', 'Ver todo', 'Tout afficher'),
            ),
          ),
      ],
    ),
  );
}

class DashboardLoadingTile extends StatelessWidget {
  const DashboardLoadingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class DashboardErrorTile extends StatelessWidget {
  final String message;
  const DashboardErrorTile({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: context.appColors.error, fontSize: 13),
      ),
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(
            BorderSide(color: context.appColors.cardBorder),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: context.appColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
