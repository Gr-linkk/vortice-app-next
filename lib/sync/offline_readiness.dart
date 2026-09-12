import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_workspace.dart';
import 'package:vortice_app/features/assets/client_team_asset_access.dart';
import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_repository.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OfflineReadiness {
  const OfflineReadiness({
    this.updatedAt,
    this.refreshing = false,
    this.needsAttention = false,
  });
  final DateTime? updatedAt;
  final bool refreshing;
  final bool needsAttention;
  bool readyAt(DateTime now) =>
      updatedAt != null &&
      !now.difference(updatedAt!).isNegative &&
      now.difference(updatedAt!) < const Duration(hours: 24);
}

/// Current assignments pin their publication even after it leaves the library.
/// Warming those items must not reactivate that template or substitute a newer one.
Set<String> offlineChecklistTemplateIds(
  Iterable<ChecklistTemplate> templates,
  Iterable<Map<String, dynamic>> assignments,
) => {
  for (final template in templates)
    if (template.isActive) template.id,
  for (final assignment in assignments)
    if (['pending', 'in_progress'].contains(assignment['status']) &&
        (assignment['checklist_templates'] as Map?)?['id'] is String)
      (assignment['checklist_templates'] as Map)['id'] as String,
};

Future<void> warmOfflineChecklistTemplates({
  required ChecklistRepository repository,
  required ChecklistSourceRepository sources,
  required Iterable<ChecklistTemplate> templates,
  required Iterable<Map<String, dynamic>> assignments,
  required void Function() check,
}) async {
  for (final id in offlineChecklistTemplateIds(templates, assignments)) {
    check();
    final items = await repository.listItemsForTemplate(id);
    check();
    await sources.prefetch(items.map((item) => item.toJson()));
    check();
  }
}

/// One refresh per account. Every asynchronous boundary checks identity and
/// the read-permission epoch. Drafts and the outbox are never modified here.
class OfflineReadinessController extends StateNotifier<OfflineReadiness> {
  OfflineReadinessController({
    required this.account,
    required this.currentAccount,
    required this.refreshRecords,
    this.now = DateTime.now,
  }) : super(const OfflineReadiness());
  final String account;
  final String? Function() currentAccount;
  final Future<void> Function(void Function() check) refreshRecords;
  final DateTime Function() now;
  bool _busy = false;
  bool _disposed = false;
  DateTime? _lastAttempt;
  String get _key => accountStorageKey(account, 'cache:offline_readiness');
  String get _epochKey => accountStorageKey(account, 'read_epoch');

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || currentAccount() != account || _busy) return;
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final stored = jsonDecode(raw) as Map;
      if (stored['epoch'] != (prefs.getInt(_epochKey) ?? 0)) return;
      state = OfflineReadiness(
        updatedAt: DateTime.tryParse(stored['updatedAt'] as String),
      );
    } catch (_) {
      /* Invalid receipt is not readiness. */
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (_busy || _disposed || currentAccount() != account) return;
    if (!force &&
        _lastAttempt != null &&
        now().difference(_lastAttempt!) < const Duration(minutes: 5)) {
      return;
    }
    _busy = true;
    _lastAttempt = now();
    final prefs = await SharedPreferences.getInstance();
    final epoch = prefs.getInt(_epochKey) ?? 0;
    void check() {
      if (_disposed ||
          currentAccount() != account ||
          (prefs.getInt(_epochKey) ?? 0) != epoch) {
        throw const AccountChangedException();
      }
    }

    try {
      check();
      state = OfflineReadiness(updatedAt: state.updatedAt, refreshing: true);
      await withFreshAccountReads(() => refreshRecords(check));
      check();
      final completed = now();
      await prefs.setString(
        _key,
        jsonEncode({
          'updatedAt': completed.toUtc().toIso8601String(),
          'epoch': epoch,
        }),
      );
      check();
      state = OfflineReadiness(updatedAt: completed);
    } catch (error) {
      if (!_disposed && currentAccount() == account) {
        final revoked =
            error is AccountChangedException || isAccessDenial(error);
        state = OfflineReadiness(
          updatedAt: revoked ? null : state.updatedAt,
          needsAttention: !isConnectionFailure(error),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final offlineReadinessProvider =
    StateNotifierProvider<OfflineReadinessController, OfflineReadiness>((ref) {
      ref.watch(
        profileProvider.select(
          (value) => (
            value.valueOrNull?.id,
            value.valueOrNull?.orgId,
            value.valueOrNull?.role,
          ),
        ),
      );
      final profile = ref.read(profileProvider).valueOrNull;
      final account =
          ref.watch(sessionProvider.select((session) => session?.user.id)) ??
          'signed_out';
      // Recreate when the organization/role changes even within the same identity.
      final organization = profile?.orgId;
      final role = profile?.role;
      final controller = OfflineReadinessController(
        account: account,
        currentAccount: () => supabase.auth.currentUser?.id,
        refreshRecords: (check) async {
          Future<T> refreshRead<T>(Refreshable<Future<T>> provider) =>
              ref.refresh(provider);
          if (profile == null ||
              profile.orgId != organization ||
              profile.role != role) {
            throw const AccountChangedException();
          }
          check();
          // Refresh providers, not their already resolved in-memory value.
          final accountCache = AccountJsonCache(
            account,
            () => supabase.auth.currentUser?.id,
          );
          final currentProfile = await accountCache.readThrough(
            'profile',
            () => supabase
                .from(AppConstants.tProfiles)
                .select()
                .eq('id', account)
                .maybeSingle()
                .timeout(const Duration(seconds: 6)),
          );
          check();
          if (currentProfile is Map && currentProfile['role'] == 'member') {
            await accountCache.readThrough(
              'organization_context',
              () => supabase
                  .rpc('organization_context')
                  .timeout(const Duration(seconds: 6)),
            );
            // Membership changes rotate the read epoch and remove the raw
            // profile too. Preserve identity, then rebuild its current role.
            await accountCache.save('profile', currentProfile);
            try {
              check();
            } on AccountChangedException {
              ref.invalidate(profileProvider);
              rethrow;
            }
          }
          await refreshRead(currentUserOrgProvider.future);
          check();
          await refreshRead(assetsProvider.future);
          check();
          await refreshRead(currentClientFleetAssetsProvider.future);
          check();
          final assets = await refreshRead(visibleAssetsProvider.future);
          check();
          await refreshRead(assetWorkspaceProvider.future);
          check();
          for (final client in assets.map((a) => a.clientId).toSet()) {
            await refreshRead(clientCapabilitiesProvider(client).future);
            check();
          }
          final repository = ref.read(checklistRepositoryProvider);
          final sources = ref.read(checklistSourceRepositoryProvider);
          final templates = await repository.listTemplates();
          check();
          final assignments = await refreshRead(
            myChecklistAssignmentsProvider.future,
          );
          check();
          await warmOfflineChecklistTemplates(
            repository: repository,
            sources: sources,
            templates: templates,
            assignments: assignments,
            check: check,
          );
          await refreshRead(operatorAssignedAssetsProvider.future);
          check();
          for (final asset in assets) {
            await refreshRead(assetByIdProvider(asset.id).future);
            check();
            await refreshRead(enginesForAssetProvider(asset.id).future);
            check();
          }
          if (canUseMaintenance(profile.role) ||
              profile.membershipManaged &&
                  (profile.canInOrganization('work_assigned') ||
                      profile.canInOrganization('planning'))) {
            final maintenance = ref.read(maintenanceRepositoryProvider);
            await maintenance.workspace();
            check();
            final jobs = await maintenance.jobs();
            check();
            for (final job in jobs.where((j) => j.status != 'closed')) {
              final detail = await maintenance.jobs(jobId: job.id);
              check();
              for (final current in detail) {
                await sources.prefetch(current.checklist);
              }
              check();
            }
            await refreshRead(maintenancePlanningProvider(null).future);
            check();
            for (final asset in jobs.map((j) => j.assetId).toSet()) {
              await maintenance.assetContext(asset);
              check();
              await refreshRead(maintenancePlanningProvider(asset).future);
              check();
            }
          }
          if (profile.role == UserRole.owner ||
              profile.role == UserRole.employee ||
              profile.role == UserRole.clientMechanic ||
              profile.membershipManaged) {
            final work = await ref
                .read(workOrderRepositoryProvider)
                .listWorkOrders();
            check();
            for (final order in work.where(
              (w) =>
                  w.status != WorkOrderStatus.closed &&
                  w.status != WorkOrderStatus.invoiced,
            )) {
              if (order.providerOrganizationId != null) {
                final context = await ref
                    .read(organizationWorkRepositoryProvider)
                    .context(order.id);
                check();
                await sources.prefetch(
                  maintenanceRows(context['checklist_snapshot']),
                );
                check();
              }
              final snapshot = await workOrderChecklistSnapshotRepository
                  .fetchByWorkOrderId(order.id);
              check();
              if (snapshot != null) {
                await repository.cacheSnapshot(snapshot);
                await sources.prefetch(
                  snapshot.items.map((item) => item.toJson()),
                );
              }
              check();
            }
          }
        },
      );
      unawaited(controller.restore());
      return controller;
    });
