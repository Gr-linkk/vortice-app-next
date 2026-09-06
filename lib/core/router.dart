import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/maintenance/maintenance_list_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_asset_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_shell.dart';
import 'package:vortice_app/core/more_screen.dart';
import 'package:vortice_app/core/router_redirect.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_screen.dart';
import 'package:vortice_app/features/fleet/fault_report_screen.dart';
import 'package:vortice_app/features/fleet/fault_detail_screen.dart';
import 'package:vortice_app/features/fleet/availability_screen.dart';
import 'package:vortice_app/features/assets/add_asset_screen.dart';
import 'package:vortice_app/features/assets/asset_detail_screen.dart';
import 'package:vortice_app/features/assets/asset_list_screen.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/login_screen.dart';
import 'package:vortice_app/features/auth/register_screen.dart';
import 'package:vortice_app/features/checklists/checklist_screen.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_router.dart';
import 'package:vortice_app/features/dashboard/employee_dashboard.dart';
import 'package:vortice_app/features/dashboard/owner_dashboard.dart';
import 'package:vortice_app/features/invoices/invoice_screen.dart';
import 'package:vortice_app/features/invoices/invoice_detail_screen.dart';
import 'package:vortice_app/features/operator/operator_checklist_screen.dart';
import 'package:vortice_app/features/parts/parts_log_screen.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_setup_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_screen.dart';
import 'package:vortice_app/features/work_orders/create_work_order_screen.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_screen.dart';
import 'package:vortice_app/features/work_orders/work_order_list_screen.dart';
import 'package:vortice_app/features/engines/engine_screen.dart';
import 'package:vortice_app/features/hours/hour_log_screen.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/clients/client_screen.dart';
import 'package:vortice_app/features/org_codes/org_code_screen.dart';
import 'package:vortice_app/features/reminders/reminder_screen.dart';
import 'package:vortice_app/features/clients/pre_trip_results_screen.dart';
import 'package:vortice_app/features/clients/asset_checklist_history_screen.dart';
import 'package:vortice_app/features/notifications/notifications_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_list_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_detail_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_authoring_policy.dart';
import 'package:vortice_app/features/service_requests/service_request_form_screen.dart';
import 'package:vortice_app/features/service_requests/service_request_list_screen.dart';
import 'package:vortice_app/features/orgs/org_admin_screen.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/service_intervals/service_interval_screen.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_telemetry.dart';
import 'package:vortice_app/features/telemetry/telemetry_history_screen.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_screen.dart';
import 'package:vortice_app/models/client_capability.dart';

// ── Router notifier — bridges Riverpod auth state into GoRouter.refreshListenable ──

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _authStatus = _ref.read(authStatusProvider);
    _ref.listen<AppAuthStatus>(authStatusProvider, (_, next) {
      _authStatus = next;
      // Defer refresh so GoRouter does not redirect while the shell tree is
      // still rebuilding/unmounting — synchronous refresh causes InheritedWidget
      // descendant assertions on logout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
    });
  }

  final Ref _ref;
  late AppAuthStatus _authStatus;

  AppAuthStatus get authStatus => _authStatus;
}

final _routerNotifierProvider = ChangeNotifierProvider<_RouterNotifier>((ref) {
  return _RouterNotifier(ref);
});

// ── Navigator keys ─────────────────────────────────────────────────────────
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

// Shell navigator key — required for Android back button to pop within shell.
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// ── Router provider ─────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(_routerNotifierProvider);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      return resolveAuthRedirect(
        authStatus: notifier.authStatus,
        location: state.matchedLocation,
      );
    },
    routes: [
      // ── Unauthenticated ────────────────────────────────────────────────
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Service report authoring is full-screen. Keeping it outside the tab
      // shell prevents the shell bottom navigation from competing with the
      // report footer and keyboard on phone-sized layouts.
      GoRoute(
        path: '/owner/service-reports/new',
        redirect: (_, state) => serviceReportAuthoringRedirect(
          historyRoute: '/owner/service-reports',
          workOrderId: state.uri.queryParameters['workOrderId'],
        ),
        builder: (_, state) => ServiceReportScreen(
          initialWorkOrderId: state.uri.queryParameters['workOrderId'],
        ),
      ),
      GoRoute(
        path: '/employee/service-reports/new',
        redirect: (_, state) => serviceReportAuthoringRedirect(
          historyRoute: '/employee/service-reports',
          workOrderId: state.uri.queryParameters['workOrderId'],
        ),
        builder: (_, state) => ServiceReportScreen(
          initialWorkOrderId: state.uri.queryParameters['workOrderId'],
        ),
      ),
      GoRoute(
        path: '/client/service-reports/new',
        redirect: (_, __) => '/client/service-reports',
      ),

      // ── Authenticated shell ────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          navigatorKey: _shellNavigatorKey,
          child: child,
        ),
        routes: [
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          GoRoute(
            path: '/fleet',
            builder: (_, state) => FleetScreen(
              assetId: state.uri.queryParameters['assetId'],
              initialTab: state.uri.queryParameters['tab'] == 'availability'
                  ? 1
                  : 0,
            ),
          ),
          GoRoute(
            path: '/fleet/report',
            builder: (_, state) => FaultReportScreen(
              assetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/fleet/faults/:id',
            builder: (_, state) =>
                FaultDetailScreen(faultId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/fleet/assets/:id',
            builder: (_, state) =>
                AvailabilityScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/maintenance',
            builder: (_, state) => MaintenanceListScreen(
              assetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/maintenance/new',
            builder: (_, state) => MaintenanceCreateScreen(
              assetId: state.uri.queryParameters['assetId'],
              planId: state.uri.queryParameters['planId'],
              parentJobId: state.uri.queryParameters['parentJobId'],
            ),
          ),
          GoRoute(
            path: '/maintenance/jobs/:id',
            builder: (_, state) =>
                MaintenanceJobScreen(jobId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/maintenance/assets',
            builder: (_, __) => const MaintenanceAssetsScreen(),
          ),
          GoRoute(
            path: '/maintenance/assets/:id',
            builder: (_, state) =>
                MaintenanceAssetScreen(assetId: state.pathParameters['id']!),
          ),
          // Owner
          GoRoute(
            path: '/owner/dashboard',
            builder: (_, __) => const OwnerDashboard(),
          ),
          GoRoute(
            path: '/owner/assets',
            builder: (_, __) => const AssetListScreen(),
          ),
          GoRoute(
            path: '/owner/assets/add',
            builder: (_, __) => const AddAssetScreen(),
          ),
          GoRoute(
            path: '/owner/assets/:id',
            builder: (_, state) =>
                AssetDetailScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/work-orders',
            builder: (_, __) => const WorkOrderListScreen(),
          ),
          GoRoute(
            path: '/owner/service-requests',
            builder: (_, __) => const StaffServiceRequestListScreen(),
          ),
          GoRoute(
            path: '/owner/work-orders/create',
            builder: (_, state) => CreateWorkOrderScreen(
              initialDraft: MaintenanceWorkOrderDraft.fromQueryParameters(
                state.uri.queryParameters,
              ),
            ),
          ),
          GoRoute(
            path: '/owner/work-orders/:id',
            builder: (_, state) =>
                WorkOrderDetailScreen(workOrderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/service-reports',
            builder: (_, state) => ServiceReportListScreen(
              initialWorkOrderId: state.uri.queryParameters['workOrderId'],
              initialAssetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/owner/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(
              reportId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/owner/parts',
            builder: (_, __) => const OwnerPartsScreen(),
          ),
          GoRoute(
            path: '/owner/invoices',
            builder: (_, __) => const InvoiceScreen(),
          ),
          GoRoute(
            path: '/owner/invoices/:id',
            builder: (_, state) =>
                InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/assets/:id/engines',
            builder: (_, state) =>
                EngineScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/assets/:id/service-intervals',
            builder: (_, state) =>
                ServiceIntervalScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/owner/assets/:id/checklist-history',
            builder: (_, state) => AssetChecklistHistoryScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
              role: ref.read(profileProvider).valueOrNull?.role,
            ),
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
              assetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/owner/clients',
            builder: (_, __) => const ClientScreen(),
          ),
          GoRoute(
            path: '/owner/org-codes',
            builder: (_, __) => const OrgCodeScreen(),
          ),
          GoRoute(
            path: '/owner/reminders',
            builder: (_, __) => const ReminderScreen(),
          ),
          GoRoute(
            path: '/owner/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/owner/checklists/:workOrderId',
            builder: (_, state) => ChecklistScreen(
              workOrderId: state.pathParameters['workOrderId']!,
            ),
          ),
          GoRoute(
            path: '/owner/checklists/:templateId/parts',
            builder: (_, state) => PmPartsSetupScreen(
              templateId: state.pathParameters['templateId']!,
              templateName: state.uri.queryParameters['name'] ?? 'Template',
            ),
          ),

          // Employee
          GoRoute(
            path: '/employee/assets',
            builder: (_, __) => const AssetListScreen(),
          ),
          GoRoute(
            path: '/employee/assets/:id',
            builder: (_, state) =>
                AssetDetailScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employee/dashboard',
            builder: (_, __) => const EmployeeDashboard(),
          ),
          GoRoute(
            path: '/employee/service-requests',
            builder: (_, __) => const StaffServiceRequestListScreen(),
          ),
          GoRoute(
            path: '/employee/work-orders',
            builder: (_, __) => const WorkOrderListScreen(),
          ),
          GoRoute(
            path: '/employee/work-orders/create',
            builder: (_, state) => CreateWorkOrderScreen(
              initialDraft: MaintenanceWorkOrderDraft.fromQueryParameters(
                state.uri.queryParameters,
              ),
            ),
          ),
          GoRoute(
            path: '/employee/work-orders/:id',
            builder: (_, state) =>
                WorkOrderDetailScreen(workOrderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/employee/checklists/:workOrderId',
            builder: (_, state) => ChecklistScreen(
              workOrderId: state.pathParameters['workOrderId']!,
            ),
          ),
          GoRoute(
            path: '/employee/assets/:id/checklist-history',
            builder: (_, state) => AssetChecklistHistoryScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
              role: ref.read(profileProvider).valueOrNull?.role,
            ),
          ),
          GoRoute(
            path: '/employee/service-reports',
            builder: (_, state) => ServiceReportListScreen(
              initialWorkOrderId: state.uri.queryParameters['workOrderId'],
              initialAssetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/employee/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(
              reportId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/employee/parts',
            builder: (_, __) => const PartsLogScreen(),
          ),

          // Client
          GoRoute(
            path: '/client/dashboard',
            builder: (_, __) => const ClientDashboardRouter(),
          ),
          GoRoute(
            path: '/meeting-request',
            redirect: (_, __) => '/client/dashboard',
          ),
          GoRoute(
            path: '/client/service-requests',
            builder: (_, __) => const ClientServiceRequestListScreen(),
          ),
          GoRoute(
            path: '/client/service-requests/new',
            builder: (_, __) => const ServiceRequestFormScreen(),
          ),
          GoRoute(
            path: '/client/assets',
            builder: (_, __) => const AssetListScreen(),
          ),
          GoRoute(
            path: '/client/assets/:id',
            builder: (_, state) =>
                AssetDetailScreen(assetId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/client/assets/:id/maintenance-plan',
            builder: (_, state) => ServiceIntervalScreen(
              assetId: state.pathParameters['id']!,
              readOnly: true,
            ),
          ),
          GoRoute(
            path: '/client/assets/:id/checklist-history',
            builder: (_, state) => AssetChecklistHistoryScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
              role: ref.read(profileProvider).valueOrNull?.role,
            ),
          ),
          GoRoute(
            path: '/client/assets/:id/checklists/new',
            builder: (_, state) => ClientCapabilityGate(
              clientId: state.uri.queryParameters['clientId'],
              capability: ClientCapability.pmChecklists,
              allowedBuilder: (_) => ChecklistScreen(
                assetId: state.pathParameters['id']!,
                assetClientId: state.uri.queryParameters['clientId'],
                assetName: state.uri.queryParameters['name'] ?? 'Asset',
                assetTypeId: state.uri.queryParameters['assetTypeId'],
                clientHistoryOnly: true,
                preSelectedTemplateId: state.uri.queryParameters['templateId'],
              ),
              blockedBuilder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Checklist')),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: ClientCapabilityDisabledPanel(
                      capability: ClientCapability.pmChecklists,
                      message:
                          'PM / mechanic checklists are not enabled for this client.',
                    ),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/client/work-orders',
            redirect: (_, __) => '/client/dashboard',
          ),
          GoRoute(
            path: '/client/work-orders/:id',
            redirect: (_, __) => '/client/dashboard',
          ),
          GoRoute(
            path: '/client/checklists/:workOrderId',
            redirect: (_, __) => '/client/dashboard',
          ),
          GoRoute(
            path: '/client/invoices',
            builder: (_, __) => const InvoiceScreen(),
          ),
          GoRoute(
            path: '/client/invoices/:id',
            builder: (_, state) =>
                InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/client/engines/:engineId/telemetry',
            builder: (_, state) => TelemetryHistoryScreen(
              engineId: state.pathParameters['engineId']!,
              assetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/client/assets/:id/pre-trip',
            builder: (_, state) => PreTripResultsScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
            ),
          ),
          GoRoute(
            path: '/client/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/client/service-reports',
            builder: (_, state) => ServiceReportListScreen(
              initialWorkOrderId: state.uri.queryParameters['workOrderId'],
              initialAssetId: state.uri.queryParameters['assetId'],
            ),
          ),
          GoRoute(
            path: '/client/service-reports/:id',
            builder: (_, state) => ServiceReportDetailScreen(
              reportId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/client/assets/:id/flags',
            builder: (_, state) =>
                FleetScreen(assetId: state.pathParameters['id']!),
          ),

          // Operator
          GoRoute(
            path: '/operator/dashboard',
            redirect: (_, __) => '/client/dashboard',
          ),
          GoRoute(
            path: '/operator/assets/:id/checklist-history',
            builder: (_, state) => AssetChecklistHistoryScreen(
              assetId: state.pathParameters['id']!,
              assetName: state.uri.queryParameters['name'] ?? 'Asset',
              role: ref.read(profileProvider).valueOrNull?.role,
            ),
          ),
          GoRoute(
            path: '/operator/checklist',
            builder: (_, state) => _OperatorChecklistCapabilityGate(
              initialAssetId: state.uri.queryParameters['assetId'],
              initialTemplateId: state.uri.queryParameters['templateId'],
            ),
          ),
          GoRoute(
            path: '/operator/flags',
            builder: (_, __) => const FaultReportScreen(),
          ),

          // Org admin
          GoRoute(
            path: '/org/admin',
            builder: (_, __) => const OrgAdminScreen(),
          ),

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
            path: '/telemetry/assets/:assetId/history',
            builder: (_, state) => TelemetryHistoryScreen(
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
  ref.onDispose(router.dispose);
  return router;
});

class _OperatorChecklistCapabilityGate extends ConsumerWidget {
  const _OperatorChecklistCapabilityGate({
    required this.initialAssetId,
    required this.initialTemplateId,
  });

  final String? initialAssetId;
  final String? initialTemplateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetId = initialAssetId;
    final assetAsync = assetId == null
        ? null
        : ref.watch(assetByIdProvider(assetId));
    final clientId = assetAsync?.valueOrNull?.clientId;

    if (assetAsync?.isLoading == true && clientId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (assetAsync?.hasError == true && clientId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checklist')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              friendlyError(context, assetAsync!.asError!.error),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
      );
    }

    return ClientCapabilityGate(
      clientId: clientId,
      capability: ClientCapability.operationalChecklists,
      allowedBuilder: (_) => OperatorChecklistScreen(
        initialAssetId: initialAssetId,
        initialTemplateId: initialTemplateId,
      ),
      blockedBuilder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Checklist')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: ClientCapabilityDisabledPanel(
              capability: ClientCapability.operationalChecklists,
              message:
                  'Operational checklists are not enabled for this client.',
            ),
          ),
        ),
      ),
    );
  }
}
