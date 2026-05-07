import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}

List<_NavItem> _clientNavItems(AppLocalizations l10n, Profile? profile) {
  return [
    _NavItem(
      label: l10n.navDashboard,
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      route: '/client/dashboard',
    ),
    _NavItem(
      label: l10n.navAssets,
      icon: Icons.directions_boat_outlined,
      activeIcon: Icons.directions_boat,
      route: '/client/assets',
    ),
    _NavItem(
      label: l10n.navInvoices,
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      route: '/client/invoices',
    ),
    const _NavItem(
      label: 'Requests',
      icon: Icons.support_agent_outlined,
      activeIcon: Icons.support_agent,
      route: '/client/service-requests',
    ),
    const _NavItem(
      label: 'Team',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups,
      route: '/org/admin',
    ),
  ];
}

List<_NavItem> _navItemsFor(
  UserRole role,
  AppLocalizations l10n,
  Profile? profile, {
  bool operationalChecklistsEnabled = false,
}) {
  return switch (role) {
    UserRole.owner => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/owner/dashboard',
        ),
        _NavItem(
          label: l10n.navAssets,
          icon: Icons.directions_boat_outlined,
          activeIcon: Icons.directions_boat,
          route: '/owner/assets',
        ),
        _NavItem(
          label: l10n.navWorkOrders,
          icon: Icons.build_outlined,
          activeIcon: Icons.build,
          route: '/owner/work-orders',
        ),
        _NavItem(
          label: l10n.navServiceReports,
          icon: Icons.description_outlined,
          activeIcon: Icons.description,
          route: '/owner/service-reports',
        ),
        _NavItem(
          label: l10n.navInvoices,
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          route: '/owner/invoices',
        ),
      ],
    UserRole.employee => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/employee/dashboard',
        ),
        _NavItem(
          label: l10n.navWorkOrders,
          icon: Icons.build_outlined,
          activeIcon: Icons.build,
          route: '/employee/work-orders',
        ),
        const _NavItem(
          label: 'Requests',
          icon: Icons.support_agent_outlined,
          activeIcon: Icons.support_agent,
          route: '/employee/service-requests',
        ),
        _NavItem(
          label: l10n.navServiceReports,
          icon: Icons.description_outlined,
          activeIcon: Icons.description,
          route: '/employee/service-reports',
        ),
        _NavItem(
          label: l10n.navParts,
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings,
          route: '/employee/parts',
        ),
      ],
    UserRole.client => _clientNavItems(l10n, profile),
    UserRole.operator => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/client/dashboard',
        ),
        if (operationalChecklistsEnabled)
          _NavItem(
            label: l10n.navChecklist,
            icon: Icons.checklist_outlined,
            activeIcon: Icons.checklist,
            route: '/operator/checklist',
          ),
        _NavItem(
          label: l10n.navFlags,
          icon: Icons.flag_outlined,
          activeIcon: Icons.flag,
          route: '/operator/flags',
        ),
      ],
    UserRole.clientAdmin => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/client/dashboard',
        ),
        _NavItem(
          label: l10n.navAssets,
          icon: Icons.directions_boat_outlined,
          activeIcon: Icons.directions_boat,
          route: '/client/assets',
        ),
        _NavItem(
          label: l10n.navInvoices,
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          route: '/client/invoices',
        ),
        const _NavItem(
          label: 'Requests',
          icon: Icons.support_agent_outlined,
          activeIcon: Icons.support_agent,
          route: '/client/service-requests',
        ),
        const _NavItem(
          label: 'Team',
          icon: Icons.groups_outlined,
          activeIcon: Icons.groups,
          route: '/org/admin',
        ),
      ],
    UserRole.clientMechanic => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/client/dashboard',
        ),
        if (operationalChecklistsEnabled)
          _NavItem(
            label: l10n.navChecklist,
            icon: Icons.checklist_outlined,
            activeIcon: Icons.checklist,
            route: '/operator/checklist',
          ),
        _NavItem(
          label: l10n.navFlags,
          icon: Icons.flag_outlined,
          activeIcon: Icons.flag,
          route: '/operator/flags',
        ),
      ],
    UserRole.clientOperator => [
        _NavItem(
          label: l10n.navDashboard,
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          route: '/client/dashboard',
        ),
        if (operationalChecklistsEnabled)
          _NavItem(
            label: l10n.navChecklist,
            icon: Icons.checklist_outlined,
            activeIcon: Icons.checklist,
            route: '/operator/checklist',
          ),
        _NavItem(
          label: l10n.navFlags,
          icon: Icons.flag_outlined,
          activeIcon: Icons.flag,
          route: '/operator/flags',
        ),
      ],
  };
}

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.employee;
    final operationalChecklistsEnabled = ref
            .watch(clientCapabilityGateProvider((
              clientId: null,
              capability: ClientCapability.operationalChecklists,
            )))
            .valueOrNull ??
        false;
    final items = _navItemsFor(
      role,
      l10n,
      profile,
      operationalChecklistsEnabled: operationalChecklistsEnabled,
    );

    final currentIndex = () {
      for (var i = 0; i < items.length; i++) {
        if (location.startsWith(items[i].route)) return i;
      }
      return 0;
    }();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.mounted) {
          final router = GoRouter.of(context);
          if (router.canPop()) {
            router.pop();
          }
        }
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (index) => context.go(items[index].route),
            items: items
                .map(
                  (item) => BottomNavigationBarItem(
                    icon: Icon(item.icon),
                    activeIcon: Icon(item.activeIcon),
                    label: item.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
