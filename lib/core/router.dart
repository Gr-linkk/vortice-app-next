import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/features/assets/add_asset_screen.dart';
import 'package:vortice_app/features/assets/asset_detail_screen.dart';
import 'package:vortice_app/features/assets/asset_list_screen.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/login_screen.dart';
import 'package:vortice_app/features/auth/register_screen.dart';
import 'package:vortice_app/features/checklists/checklist_screen.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_free.dart';
import 'package:vortice_app/features/meeting/meeting_request_screen.dart';
import 'package:vortice_app/features/dashboard/employee_dashboard.dart';
import 'package:vortice_app/features/dashboard/operator_dashboard.dart';
import 'package:vortice_app/features/dashboard/owner_dashboard.dart';
import 'package:vortice_app/features/invoices/invoice_screen.dart';
import 'package:vortice_app/features/invoices/invoice_detail_screen.dart';
import 'package:vortice_app/features/operator/maintenance_flag_screen.dart';
import 'package:vortice_app/features/operator/operator_checklist_screen.dart';
import 'package:vortice_app/features/parts/parts_log_screen.dart';
import 'package:vortice_app/features/parts/parts_inventory_screen.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_setup_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_screen.dart';
import 'package:vortice_app/features/work_orders/create_work_order_screen.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_screen.dart';
import 'package:vortice_app/features/work_orders/work_order_list_screen.dart';
import 'package:vortice_app/features/engines/engine_screen.dart';
import 'package:vortice_app/features/hours/hour_log_screen.dart';
import 'package:vortice_app/features/clients/client_screen.dart';
import 'package:vortice_app/features/org_codes/org_code_screen.dart';
import 'package:vortice_app/features/reminders/reminder_screen.dart';
import 'package:vortice_app/features/clients/pre_trip_results_screen.dart';
import 'package:vortice_app/features/clients/maintenance_flags_screen.dart';
import 'package:vortice_app/features/notifications/notifications_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_list_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_detail_screen.dart';
import 'package:vortice_app/features/orgs/org_admin_screen.dart';
import 'package:vortice_app/features/service_intervals/service_interval_screen.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_telemetry.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_screen.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_screen.dart';
import 'package:vortice_app/models/profile.dart';

// ── Router notifier — bridges Riverpod auth state into GoRouter.refreshListenable ──

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen<AppAuthStatus>(authStatusProvider, (_, __) => notifyListeners());
  }
}

final _routerNotifierProvider = ChangeNotifierProvider<_RouterNotifier>((ref) {
  return _RouterNotifier(ref);
});

// ── Route helper ────────────────────────────────────────────────────────────

String _dashboardFor(UserRole? role) => switch (role) {
      UserRole.owner => '/owner/dashboard',
      UserRole.employee => '/employee/dashboard',
      UserRole.client => '/client/dashboard',
      UserRole.operator => '/client/dashboard',    // org-scoped operator dashboard
      UserRole.clientAdmin => '/client/dashboard',
      UserRole.clientMechanic => '/client/dashboard',
      UserRole.clientOperator => '/client/dashboard', // legacy — same as operator
      null => '/login',
    };

// ── Shell navigator key — required for Android back button to pop within shell ──
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// ── Router provider ─────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authStatus = ref.read(authStatusProvider);
      final location = state.matchedLocation;

      // Still loading auth — hold on the current route
      if (authStatus.isLoading) return null;

      final onAuthRoute = location == '/login' || location == '/register';

      if (!authStatus.isAuthenticated) {
        return onAuthRoute ? null : '/login';
      }

      // Authenticated — bounce off auth screens to the correct dashboard
      if (onAuthRoute) return _dashboardFor(authStatus.profile?.role);

      return null;
    },
    routes: [
      // ── Unauthenticated ────────────────────────────────────────────────
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // ── Authenticated shell ────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          // Owner
          GoRoute(path: '/owner/dashboard', builder: (_, __) => const OwnerDashboard()),
          GoRoute(path: '/owner/assets', builder: (_, __) => const AssetListScreen()),
          GoRoute(path: '/owner/assets/add', builder: (_, __) => const AddAssetScreen()),
          GoRoute(
            path: '/owner/assets/:id',
            builder: (_, state) => AssetDetailScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/owner/work-orders', builder: (_, __) => const WorkOrderListScreen()),
          GoRoute(
            path: '/owner/work-orders/create',
            builder: (_, __) => const CreateWorkOrderScreen(),
          ),
          GoRoute(
            path: '/owner/work-orders/:id',
            builder: (_, state) =>
                WorkOrderDetailScreen(workOrderId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/owner/service-reports', builder: (_, __) => const ServiceReportListScreen()),
          GoRoute(path: '/owner/service-reports/new', builder: (_, __) => const ServiceReportScreen()),
          GoRoute(
            path: '/owner/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(reportId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/owner/parts', builder: (_, __) => const OwnerPartsScreen()),
          GoRoute(path: '/owner/invoices', builder: (_, __) => const InvoiceScreen()),
          GoRoute(
            path: '/owner/invoices/:id',
            builder: (_, state) => InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/assets/:id/engines',
            builder: (_, state) => EngineScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/engines/:engineId/hours',
            builder: (_, state) => HourLogScreen(
              engineId: state.pathParameters['engineId']!,
              assetId: state.uri.queryParameters['assetId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/owner/engines/:engineId/telemetry',
            builder: (_, state) => TelemetryHistoryScreen(
              engineId: state.pathParameters['engineId']!,
            ),
          ),
          GoRoute(path: '/owner/clients', builder: (_, __) => const ClientScreen()),
          GoRoute(path: '/owner/org-codes', builder: (_, __) => const OrgCodeScreen()),
          GoRoute(path: '/owner/reminders', builder: (_, __) => const ReminderScreen()),
          GoRoute(path: '/owner/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/owner/parts/inventory', builder: (_, __) => const PartsInventoryScreen()),
          GoRoute(
            path: '/owner/checklists/:workOrderId',
            builder: (_, state) =>
                ChecklistScreen(workOrderId: state.pathParameters['workOrderId']!),
          ),
          GoRoute(
            path: '/owner/checklists/:templateId/parts',
            builder: (_, state) => PmPartsSetupScreen(
              templateId: state.pathParameters['templateId']!,
              templateName: state.uri.queryParameters['name'] ?? 'Template',
            ),
          ),

          // Employee
          GoRoute(path: '/employee/dashboard', builder: (_, __) => const EmployeeDashboard()),
          GoRoute(path: '/employee/work-orders', builder: (_, __) => const WorkOrderListScreen()),
          GoRoute(
            path: '/employee/work-orders/create',
            builder: (_, __) => const CreateWorkOrderScreen(),
          ),
          GoRoute(
            path: '/employee/work-orders/:id',
            builder: (_, state) =>
                WorkOrderDetailScreen(workOrderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employee/checklists/:workOrderId',
            builder: (_, state) =>
                ChecklistScreen(workOrderId: state.pathParameters['workOrderId']!),
          ),
          GoRoute(path: '/employee/service-reports', builder: (_, __) => const ServiceReportListScreen()),
          GoRoute(path: '/employee/service-reports/new', builder: (_, __) => const ServiceReportScreen()),
          GoRoute(
            path: '/employee/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(reportId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/employee/parts', builder: (_, __) => const PartsLogScreen()),
          GoRoute(path: '/employee/parts/inventory', builder: (_, __) => const PartsInventoryScreen()),

          // Client
          GoRoute(path: '/client/dashboard', builder: (_, __) => const ClientDashboardRouter()),
          GoRoute(path: '/meeting-request', builder: (_, __) => const MeetingRequestScreen()),
          GoRoute(path: '/client/assets', builder: (_, __) => const AssetListScreen()),
          GoRoute(
            path: '/client/assets/:id',
            builder: (_, state) => AssetDetailScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/client/work-orders', builder: (_, __) => const WorkOrderListScreen()),
          GoRoute(
            path: '/client/work-orders/:id',
            builder: (_, state) =>
                WorkOrderDetailScreen(workOrderId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/client/invoices', builder: (_, __) => const InvoiceScreen()),
          GoRoute(
            path: '/client/invoices/:id',
            builder: (_, state) => InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/client/engines/:engineId/telemetry',
            builder: (_, state) => TelemetryHistoryScreen(
              engineId: state.pathParameters['engineId']!,
            ),
          ),
          GoRoute(
            path: '/client/assets/:id/pre-trip',
            builder: (_, state) => PreTripResultsScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
            ),
          ),
          GoRoute(path: '/client/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(
            path: '/client/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(reportId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/client/assets/:id/flags',
            builder: (_, state) => MaintenanceFlagsScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
            ),
          ),

          // Operator
          GoRoute(path: '/operator/dashboard', builder: (_, __) => const OperatorDashboard()),
          GoRoute(
            path: '/operator/checklist',
            builder: (_, state) => OperatorChecklistScreen(
              initialAssetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(path: '/operator/flags', builder: (_, __) => const MaintenanceFlagScreen()),

          // Org admin
          GoRoute(path: '/org/admin', builder: (_, __) => const OrgAdminScreen()),

          // Service intervals (owner)
          GoRoute(
            path: '/service-intervals',
            builder: (_, __) => const ServiceIntervalScreen(),
          ),

          // Telemetry routes
          GoRoute(
            path: '/telemetry/vessel/:assetId',
            builder: (_, state) => VesselTelemetryScreen(
              assetId: state.pathParameters['assetId']!,
            ),
          ),
          GoRoute(
            path: '/telemetry/dashboard',
            builder: (_, __) => const ClientDashboardTelemetry(),
          ),
        ],
      ),
    ],
  );
});
