import 'package:flutter/material.dart';
import 'package:vortice_app/sync/field_sync_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';

@visibleForTesting
bool appShellShouldHideBottomNavigation(String location) {
  final path = Uri.parse(location).path;
  return path.endsWith('/new') ||
      path.endsWith('/create') ||
      path.endsWith('/add') ||
      path == '/fleet/report' ||
      path == '/operator/flags' ||
      RegExp(r'^/(owner|employee)/checklists/[^/]+$').hasMatch(path);
}

@visibleForTesting
String? appShellBackFallbackRoute(UserRole role, String location) {
  final dashboardRoute = switch (role) {
    UserRole.owner => '/owner/dashboard',
    UserRole.employee => '/employee/dashboard',
    UserRole.client ||
    UserRole.clientAdmin ||
    UserRole.clientMechanic ||
    UserRole.clientOperator ||
    UserRole.operator => '/client/dashboard',
  };

  if (location == dashboardRoute) return null;
  return dashboardRoute;
}

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStatus = ref.watch(authStatusProvider);
    if (!authStatus.isAuthenticated || authStatus.profile == null) {
      // Auth is clearing (e.g. sign-out) — skip role-specific chrome so the
      // shell can unmount cleanly before the router lands on /login.
      return Scaffold(body: child);
    }

    final es = isSpanish(context);
    final profile = authStatus.profile!;
    final role = profile.role;
    final operationalChecklistsEnabled =
        ref
            .watch(
              clientCapabilityGateProvider((
                clientId: null,
                capability: ClientCapability.operationalChecklists,
              )),
            )
            .valueOrNull ??
        false;
    final items = primaryDestinations(
      role,
      operationalChecklistsEnabled: operationalChecklistsEnabled,
    );
    final currentIndex = selectedDestination(items, location);
    final hideBottomNavigation = appShellShouldHideBottomNavigation(location);

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!context.mounted) return true;

        final navigator = navigatorKey?.currentState;
        if (navigator != null && await navigator.maybePop()) return true;

        final fallback = appShellBackFallbackRoute(role, location);
        if (fallback != null && fallback != location && context.mounted) {
          context.go(fallback);
        }

        // Swallow Android system back inside the authenticated shell. The app
        // should move within Vórtice navigation, not accidentally close from a
        // leaf screen or top-level tab.
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const FieldSyncStatus(),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: hideBottomNavigation
            ? null
            : Container(
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
                          activeIcon: Icon(item.icon),
                          label: item.label(es),
                        ),
                      )
                      .toList(),
                ),
              ),
      ),
    );
  }
}
