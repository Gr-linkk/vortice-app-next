import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/route_access_policy.dart';
import 'package:vortice_app/core/router_redirect.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/profile.dart';

class RouteQaScreen extends StatelessWidget {
  const RouteQaScreen({super.key});

  static const _roles = <_QaRole>[
    _QaRole('Client', UserRole.client),
    _QaRole('Client Admin', UserRole.clientAdmin),
    _QaRole('Client Mechanic', UserRole.clientMechanic),
    _QaRole('Client Operator', UserRole.clientOperator),
    _QaRole('Operator', UserRole.operator),
  ];

  static const _routes = <_QaRoute>[
    _QaRoute('/client/work-orders'),
    _QaRoute('/client/work-orders/wo-test'),
    _QaRoute('/client/checklists/wo-test'),
    _QaRoute('/client/service-reports/new'),
    _QaRoute('/meeting-request'),
    _QaRoute('/client/service-reports'),
    _QaRoute('/client/assets/asset-test'),
  ];

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final role in _roles)
        for (final route in _routes)
          RouteQaResult(
            roleLabel: role.label,
            route: route.path,
            expectedRedirect: expectedRouteQaRedirect(
              role: role.role,
              location: route.path,
            ),
            actualRedirect: resolveRouteAccessRedirect(
              role: role.role,
              location: route.path,
              dashboardRouteForRole: dashboardRouteForRole,
            ),
          ),
    ];

    final failures = results.where((result) => !result.passed).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route QA'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to login',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StatusPill(
                passed: failures.isEmpty,
                label: failures.isEmpty
                    ? 'All checks pass'
                    : '${failures.length} failing',
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Debug route matrix',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Confirms sensitive client routes redirect before a phone smoke test.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final role in _roles) ...[
            Text(
              role.label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            for (final result in results.where(
              (result) => result.roleLabel == role.label,
            ))
              _RouteQaResultTile(result: result),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

@visibleForTesting
String? expectedRouteQaRedirect({
  required UserRole role,
  required String location,
}) {
  if (isRetiredMeetingRequestRoute(location) ||
      isClientInternalWorkOrderRoute(location)) {
    return dashboardRouteForRole(role);
  }

  if (isClientServiceReportAuthoringRoute(location) &&
      !isVorticeStaffRole(role)) {
    return '/client/service-reports';
  }

  return null;
}

@visibleForTesting
class RouteQaResult {
  const RouteQaResult({
    required this.roleLabel,
    required this.route,
    required this.expectedRedirect,
    required this.actualRedirect,
  });

  final String roleLabel;
  final String route;
  final String? expectedRedirect;
  final String? actualRedirect;

  bool get passed {
    return expectedRedirect == actualRedirect;
  }

  String get displayResult =>
      actualRedirect == null ? 'Allowed' : 'Redirects to $actualRedirect';
}

class _RouteQaResultTile extends StatelessWidget {
  const _RouteQaResultTile({required this.result});

  final RouteQaResult result;

  @override
  Widget build(BuildContext context) {
    final icon = result.passed ? Icons.check_circle : Icons.error;
    final color = result.passed ? AppColors.success : AppColors.error;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          result.route,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          result.displayResult,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _StatusPill(
          passed: result.passed,
          label: result.passed ? 'PASS' : 'FAIL',
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.passed, required this.label});

  final bool passed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QaRole {
  const _QaRole(this.label, this.role);

  final String label;
  final UserRole role;
}

class _QaRoute {
  const _QaRoute(this.path);

  final String path;
}
