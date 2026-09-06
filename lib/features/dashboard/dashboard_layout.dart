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
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/sign_out_button.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/fleet/fleet_entry_card.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';

String dashboardText(BuildContext context, String en, String es) =>
    isSpanish(context) ? es : en;

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
      title: Text(dashboardText(context, 'Home', 'Inicio')),
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
      tooltip: dashboardText(context, 'Notifications', 'Notificaciones'),
      onPressed: () => context.push(route),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class DashboardList extends StatelessWidget {
  const DashboardList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(bottom: 32),
    children: [const DashboardIntro(), ...children],
  );
}

class DashboardIntro extends ConsumerWidget {
  const DashboardIntro({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.client;
    final name = profile?.fullName.trim().split(' ').first ?? '';
    final es = Localizations.localeOf(context).languageCode == 'es';
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty
                    ? (es ? 'Bienvenido' : 'Welcome back')
                    : (es ? 'Hola, $name' : 'Hi, $name'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${dashboardRoleLabel(role, es)} · ${DateFormat.MMMEd(es ? 'es' : 'en').format(DateTime.now())}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const FleetEntryCard(),
        if (canManageFleet(role)) const FleetPriorityCard(),
        DashboardSection(title: es ? 'Acciones rápidas' : 'Quick actions'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final single =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions
                    .map(
                      (action) => SizedBox(
                        width: single
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 12) / 2,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.push(action.route),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 72),
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    action.icon,
                                    color: AppColors.primaryLight,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      action.label(es),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
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
    const AppDestination(
      'Report a fault',
      'Reportar una falla',
      Icons.report_problem_outlined,
      '/fleet/report',
    ),
    if (role == UserRole.owner)
      const AppDestination(
        'New work order',
        'Nueva orden de trabajo',
        Icons.add_task,
        '/maintenance/new',
      )
    else if (role == UserRole.employee)
      const AppDestination(
        'Work orders',
        'Órdenes de trabajo',
        Icons.build_outlined,
        '/maintenance',
      )
    else if (admin)
      const AppDestination(
        'New maintenance job',
        'Crear trabajo',
        Icons.add_task,
        '/maintenance/new',
      )
    else if (role == UserRole.clientMechanic)
      const AppDestination(
        'My Work',
        'Mi trabajo',
        Icons.build_outlined,
        '/maintenance',
      )
    else if (operationalChecklistsEnabled &&
        (role == UserRole.operator || role == UserRole.clientOperator))
      const AppDestination(
        'Start checklist',
        'Iniciar revisión',
        Icons.checklist,
        '/operator/checklist',
      )
    else
      AppDestination(
        'View assets',
        'Ver equipos',
        Icons.directions_boat_outlined,
        '$prefix/assets',
      ),
    if (staff)
      AppDestination(
        'Service requests',
        'Solicitudes de servicio',
        Icons.support_agent,
        '$prefix/service-requests',
      )
    else if (admin || role == UserRole.clientMechanic)
      const AppDestination(
        'Service reports',
        'Informes de servicio',
        Icons.description_outlined,
        '/client/service-reports',
      )
    else if (operationalChecklistsEnabled)
      AppDestination(
        'View assets',
        'Ver equipos',
        Icons.directions_boat_outlined,
        '$prefix/assets',
      )
    else
      const AppDestination(
        'Notifications',
        'Notificaciones',
        Icons.notifications_outlined,
        '/notifications',
      ),
    const AppDestination(
      'All tools',
      'Todas las herramientas',
      Icons.grid_view_outlined,
      '/more',
    ),
  ];
}

String dashboardRoleLabel(UserRole role, bool es) => switch (role) {
  UserRole.owner => es ? 'Administración' : 'Administration',
  UserRole.employee => es ? 'Equipo de servicio' : 'Service team',
  UserRole.client || UserRole.clientAdmin => es ? 'Mi empresa' : 'My company',
  UserRole.clientMechanic => es ? 'Mecánico' : 'Mechanic',
  UserRole.operator || UserRole.clientOperator => es ? 'Operador' : 'Operator',
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
            child: Text(dashboardText(context, 'View all', 'Ver todo')),
          ),
      ],
    ),
  );
}
