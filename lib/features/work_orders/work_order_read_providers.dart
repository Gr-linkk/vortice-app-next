import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_profile_cache.dart';
import 'package:vortice_app/features/work_orders/work_order_repository.dart';
import 'package:vortice_app/features/work_orders/work_order_support.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/models/work_order_assignment.dart';

final workOrdersProvider = FutureProvider<List<WorkOrder>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final orders = await ref.watch(workOrderRepositoryProvider).listWorkOrders();
  if (shouldBypassWorkOrderAssignmentFilter(profile?.role)) {
    return orders;
  }

  try {
    final assignments = await supabase
        .from(AppConstants.tWorkOrderAssignments)
        .select('work_order_id')
        .eq('profile_id', profile!.id);
    final assignedIds = {
      for (final row in assignments as List)
        if ((row as Map<String, dynamic>)['work_order_id'] is String)
          row['work_order_id'] as String,
    };
    return filterWorkOrdersForAssignee(
      orders: orders,
      assignedIds: assignedIds,
      profileId: profile.id,
    );
  } catch (_) {
    return filterWorkOrdersForAssignee(
      orders: orders,
      assignedIds: const {},
      profileId: profile!.id,
    );
  }
});

final workOrderByIdProvider =
    FutureProvider.family<WorkOrder?, String>((ref, id) async {
  return ref.watch(workOrderRepositoryProvider).getWorkOrderById(id);
});

final assignableWorkOrderProfilesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
  ref,
  clientId,
) async {
  final employees = await supabase
      .from(AppConstants.tProfiles)
      .select('id, full_name, role')
      .eq('role', 'employee')
      .order('full_name');

  final assignable = <Map<String, dynamic>>[
    ...(employees as List).cast<Map<String, dynamic>>(),
  ];

  if (clientId == null || clientId.isEmpty) return assignable;

  final orgRows = await supabase
      .from(AppConstants.tClientOrgs)
      .select('id')
      .eq('owner_profile_id', clientId);
  final orgIds = (orgRows as List)
      .map((row) => (row as Map<String, dynamic>)['id'])
      .whereType<String>()
      .toList();
  if (orgIds.isEmpty) return assignable;

  final clientMechanics = await supabase
      .from(AppConstants.tProfiles)
      .select('id, full_name, role')
      .eq('role', 'client_mechanic')
      .inFilter('org_id', orgIds)
      .order('full_name');

  assignable.addAll((clientMechanics as List).cast<Map<String, dynamic>>());
  return assignable;
});

final employeesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(assignableWorkOrderProfilesProvider(null).future);
});

final assetEnginesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from('asset_engines')
      .select('id, label, kind')
      .eq('asset_id', assetId);
  return (data as List).cast<Map<String, dynamic>>();
});

final assetNameProvider =
    FutureProvider.family<String?, String>((ref, assetId) async {
  final db = ref.watch(databaseProvider);
  final cached = await db.assetsDao.getById(assetId);

  try {
    final data = await supabase
        .from(AppConstants.tAssets)
        .select()
        .eq('id', assetId)
        .maybeSingle();

    if (data == null) return null;

    final asset = Asset.fromJson(data);
    await db.assetsDao.upsert(assetToCompanion(asset));
    return asset.name;
  } catch (_) {
    if (cached != null) return cached.name;
    rethrow;
  }
});

final profileNameProvider =
    FutureProvider.family<String?, String>((ref, profileId) async {
  final db = ref.watch(databaseProvider);
  final cached = await cachedProfileById(db, profileId);

  try {
    final data = await supabase
        .from(AppConstants.tProfiles)
        .select(profileSelectColumns)
        .eq('id', profileId)
        .maybeSingle();

    if (data == null) return null;

    await upsertRemoteProfile(db, data);
    return formatProfileName(data['full_name']);
  } catch (_) {
    final cachedName = formatProfileName(cached?.fullName, fallback: null);
    if (cachedName != null) return cachedName;
    rethrow;
  }
});

final latestEngineHoursProvider =
    FutureProvider.family<EngineHoursSnapshot, String>((ref, engineId) async {
  final rows = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id, title, hours_at_start, hours_at_end, updated_at, created_at')
      .eq('engine_id', engineId)
      .order('updated_at', ascending: false)
      .order('created_at', ascending: false)
      .limit(20);

  return parseLatestEngineHours((rows as List).cast<Map<String, dynamic>>());
});

final workOrderAssignmentsProvider =
    FutureProvider.family<List<WorkOrderAssignment>, String>(
        (ref, workOrderId) async {
  final data = await supabase
      .from(AppConstants.tWorkOrderAssignments)
      .select()
      .eq('work_order_id', workOrderId)
      .order('created_at');

  return (data as List)
      .map((row) => WorkOrderAssignment.fromJson(row as Map<String, dynamic>))
      .toList();
});

final currentUserAssignedToWorkOrderProvider =
    FutureProvider.family<bool, String>((ref, workOrderId) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return false;

  try {
    final assignments =
        await ref.watch(workOrderAssignmentsProvider(workOrderId).future);
    if (assignments.any((assignment) => assignment.profileId == profile.id)) {
      return true;
    }
  } catch (_) {
    // Fall back to the legacy single-assignee column below.
  }

  try {
    final workOrder =
        await ref.watch(workOrderByIdProvider(workOrderId).future);
    return workOrder?.assignedTo == profile.id;
  } catch (_) {
    return false;
  }
});

final workOrderAssignmentNamesProvider =
    FutureProvider.family<List<String>, String>((ref, workOrderId) async {
  final db = ref.watch(databaseProvider);

  try {
    final assignments =
        await ref.watch(workOrderAssignmentsProvider(workOrderId).future);
    if (assignments.isEmpty) return const [];

    final ids = assignments.map((a) => a.profileId).toList();
    final rows = await supabase
        .from(AppConstants.tProfiles)
        .select(profileSelectColumns)
        .inFilter('id', ids);

    final profileRows = (rows as List).cast<Map<String, dynamic>>();
    await upsertRemoteProfiles(db, profileRows);

    final namesById = {
      for (final row in profileRows)
        if (row['id'] is String)
          row['id'] as String: formatProfileName(row['full_name']),
    };

    return ids.map((id) => namesById[id] ?? unnamedTechLabel).toList();
  } catch (_) {
    final assignedTo = await fallbackAssignedTo(
      db,
      () => ref.read(workOrderByIdProvider(workOrderId).future),
      workOrderId,
    );
    if (assignedTo == null) rethrow;

    final cachedProfile = await cachedProfileById(db, assignedTo);
    final cachedName = formatProfileName(
      cachedProfile?.fullName,
      fallback: null,
    );
    if (cachedName == null) rethrow;
    return [cachedName];
  }
});
