import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/features/work_orders/work_order_repository.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/models/work_order_assignment.dart';

final workOrdersProvider = FutureProvider<List<WorkOrder>>((ref) async {
  return ref.watch(workOrderRepositoryProvider).listWorkOrders();
});

final workOrderByIdProvider =
    FutureProvider.family<WorkOrder?, String>((ref, id) async {
  return ref.watch(workOrderRepositoryProvider).getWorkOrderById(id);
});

Future<void> _trySyncChecklistSnapshot(
  String workOrderId,
  String? templateId,
) async {
  try {
    final payload =
        await workOrderChecklistSnapshotRepository.trySyncForWorkOrderTemplate(
      workOrderId: workOrderId,
      templateId: templateId,
    );
    final version = (payload?['template_version'] as num?)?.toInt();
    if (version != null) {
      await supabase
          .from(AppConstants.tWorkOrders)
          .update({'checklist_template_version': version}).eq(
        'id',
        workOrderId,
      );
    }
  } catch (_) {
    // Snapshot support is best-effort until every environment has the table.
  }
}

class WorkOrderController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  WorkOrderController(this._ref) : super(const AsyncData(null));

  Future<bool> createWorkOrder(
    Map<String, dynamic> data, {
    List<String> assignedProfileIds = const [],
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final workOrder = await supabase
          .from(AppConstants.tWorkOrders)
          .insert(data)
          .select('id')
          .single();

      final workOrderId = workOrder['id'] as String;
      final engineId = data['engine_id'] as String?;
      final checklistTemplateId = data['checklist_template_id'] as String?;

      if (assignedProfileIds.isNotEmpty) {
        await supabase.from(AppConstants.tWorkOrderAssignments).insert(
              assignedProfileIds
                  .map(
                    (profileId) => {
                      'work_order_id': workOrderId,
                      'profile_id': profileId,
                      'role': 'tech',
                    },
                  )
                  .toList(),
            );
      }

      await _trySyncChecklistSnapshot(workOrderId, checklistTemplateId);

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentsProvider(workOrderId));
      _ref.invalidate(workOrderAssignmentNamesProvider(workOrderId));
      if (engineId != null) {
        _ref.invalidate(latestEngineHoursProvider(engineId));
      }
      success = true;
    });
    return success;
  }

  Future<bool> updateStatus(String id, WorkOrderStatus status) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'status': status.dbValue,
        if (status == WorkOrderStatus.closed)
          'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      success = true;
    });
    return success;
  }

  Future<bool> updateWorkOrder(
    String id,
    Map<String, dynamic> data, {
    List<String>? assignedProfileIds,
  }) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final previous = await supabase
          .from(AppConstants.tWorkOrders)
          .select('engine_id')
          .eq('id', id)
          .maybeSingle();
      await supabase.from(AppConstants.tWorkOrders).update(data).eq('id', id);

      final hasChecklistUpdate = data.containsKey('checklist_template_id');
      final nextChecklistTemplateId =
          hasChecklistUpdate ? data['checklist_template_id'] as String? : null;

      if (assignedProfileIds != null) {
        await supabase
            .from(AppConstants.tWorkOrderAssignments)
            .delete()
            .eq('work_order_id', id);

        if (assignedProfileIds.isNotEmpty) {
          await supabase.from(AppConstants.tWorkOrderAssignments).insert(
                assignedProfileIds
                    .map(
                      (profileId) => {
                        'work_order_id': id,
                        'profile_id': profileId,
                        'role': 'tech',
                      },
                    )
                    .toList(),
              );
        }
      }

      if (hasChecklistUpdate) {
        await _trySyncChecklistSnapshot(id, nextChecklistTemplateId);
      }

      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      _ref.invalidate(workOrderAssignmentsProvider(id));
      _ref.invalidate(workOrderAssignmentNamesProvider(id));
      final previousEngineId = previous?['engine_id'] as String?;
      final nextEngineId = data['engine_id'] as String? ?? previousEngineId;
      if (previousEngineId != null) {
        _ref.invalidate(latestEngineHoursProvider(previousEngineId));
      }
      if (nextEngineId != null && nextEngineId != previousEngineId) {
        _ref.invalidate(latestEngineHoursProvider(nextEngineId));
      }
      success = true;
    });
    return success;
  }

  Future<bool> assignTo(String workOrderId, String userId) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'assigned_to': userId,
        'status': WorkOrderStatus.assigned.dbValue,
      }).eq('id', workOrderId);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(workOrderId));
      success = true;
    });
    return success;
  }

  Future<bool> reopenStatus(String id) async {
    state = const AsyncLoading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      await supabase.from(AppConstants.tWorkOrders).update({
        'status': WorkOrderStatus.inProgress.dbValue,
        'completed_at': null,
      }).eq('id', id);
      _ref.invalidate(workOrdersProvider);
      _ref.invalidate(workOrderByIdProvider(id));
      success = true;
    });
    return success;
  }
}

final workOrderControllerProvider =
    StateNotifierProvider<WorkOrderController, AsyncValue<void>>((ref) {
  return WorkOrderController(ref);
});

// Load employees for tech assignment
final employeesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from('profiles')
      .select('id, full_name')
      .eq('role', 'employee');
  return (data as List).cast<Map<String, dynamic>>();
});

// Load engines for a specific asset
final assetEnginesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, assetId) async {
  final data = await supabase
      .from('asset_engines')
      .select('id, label, kind')
      .eq('asset_id', assetId);
  return (data as List).cast<Map<String, dynamic>>();
});

// Fetch asset name by ID
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
    await db.assetsDao.upsert(_assetToCompanion(asset));
    return asset.name;
  } catch (_) {
    if (cached != null) return cached.name;
    rethrow;
  }
});

AssetsTableCompanion _assetToCompanion(Asset asset) => AssetsTableCompanion(
      id: Value(asset.id),
      clientId: Value(asset.clientId),
      assetTypeId: Value(asset.assetTypeId),
      name: Value(asset.name),
      make: Value(asset.make),
      model: Value(asset.model),
      year: Value(asset.year),
      serialNumber: Value(asset.serialNumber),
      location: Value(asset.location),
      notes: Value(asset.notes),
      telemetryEnabled: Value(asset.telemetryEnabled),
      telemetrySource: Value(asset.telemetrySource),
      createdAt: Value(asset.createdAt),
      updatedAt: Value(asset.updatedAt),
    );

const _profileSelectColumns =
    'id, email, full_name, role, phone, preferred_language, org_code_used, created_at, updated_at';
const _unnamedTechLabel = 'Unnamed tech';

// Fetch profile full_name by ID
final profileNameProvider =
    FutureProvider.family<String?, String>((ref, profileId) async {
  final db = ref.watch(databaseProvider);
  final cached = await _cachedProfileById(db, profileId);

  try {
    final data = await supabase
        .from(AppConstants.tProfiles)
        .select(_profileSelectColumns)
        .eq('id', profileId)
        .maybeSingle();

    if (data == null) return null;

    await _upsertRemoteProfile(db, data);
    return _formatProfileName(data['full_name']);
  } catch (_) {
    final cachedName = _formatProfileName(cached?.fullName, fallback: null);
    if (cachedName != null) return cachedName;
    rethrow;
  }
});

Future<ProfilesTableData?> _cachedProfileById(
  AppDatabase db,
  String profileId,
) {
  return (db.select(db.profilesTable)..where((t) => t.id.equals(profileId)))
      .getSingleOrNull();
}

Future<void> _upsertRemoteProfile(
  AppDatabase db,
  Map<String, dynamic> row,
) async {
  final id = row['id'];
  final email = row['email'];
  final fullName = row['full_name'];

  if (id is! String || email is! String || fullName is! String) {
    return;
  }

  await db.into(db.profilesTable).insertOnConflictUpdate(
        ProfilesTableCompanion(
          id: Value(id),
          email: Value(email),
          fullName: Value(fullName),
          role: Value((row['role'] as String?) ?? 'employee'),
          phone: Value(row['phone'] as String?),
          preferredLanguage:
              Value((row['preferred_language'] as String?) ?? 'en'),
          orgCodeUsed: Value(row['org_code_used'] as String?),
          createdAt: Value(_parseDateTime(row['created_at'])),
          updatedAt: Value(_parseDateTime(row['updated_at'])),
        ),
      );
}

Future<void> _upsertRemoteProfiles(
  AppDatabase db,
  Iterable<Map<String, dynamic>> rows,
) async {
  for (final row in rows) {
    await _upsertRemoteProfile(db, row);
  }
}

String? _formatProfileName(
  Object? value, {
  String? fallback = _unnamedTechLabel,
}) {
  final name = value is String ? value.trim() : '';
  if (name.isNotEmpty) return name;
  return fallback;
}

DateTime? _parseDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class EngineHoursSnapshot {
  final double? hours;
  final String? workOrderId;
  final String? title;

  const EngineHoursSnapshot({
    required this.hours,
    this.workOrderId,
    this.title,
  });
}

final latestEngineHoursProvider =
    FutureProvider.family<EngineHoursSnapshot, String>((ref, engineId) async {
  final rows = await supabase
      .from(AppConstants.tWorkOrders)
      .select('id, title, hours_at_start, hours_at_end, updated_at, created_at')
      .eq('engine_id', engineId)
      .order('updated_at', ascending: false)
      .order('created_at', ascending: false)
      .limit(20);

  final items = (rows as List).cast<Map<String, dynamic>>();
  final match = items.firstWhere(
    (row) => row['hours_at_end'] != null || row['hours_at_start'] != null,
    orElse: () => const <String, dynamic>{},
  );

  if (match.isEmpty) {
    return const EngineHoursSnapshot(hours: null);
  }

  return EngineHoursSnapshot(
    hours: (match['hours_at_end'] as num?)?.toDouble() ??
        (match['hours_at_start'] as num?)?.toDouble(),
    workOrderId: match['id'] as String?,
    title: match['title'] as String?,
  );
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
        .select(_profileSelectColumns)
        .inFilter('id', ids);

    final profileRows = (rows as List).cast<Map<String, dynamic>>();
    await _upsertRemoteProfiles(db, profileRows);

    final namesById = {
      for (final row in profileRows)
        if (row['id'] is String)
          row['id'] as String: _formatProfileName(row['full_name']),
    };

    return ids.map((id) => namesById[id] ?? _unnamedTechLabel).toList();
  } catch (_) {
    final assignedTo = await _fallbackAssignedTo(ref, db, workOrderId);
    if (assignedTo == null) rethrow;

    final cachedProfile = await _cachedProfileById(db, assignedTo);
    final cachedName = _formatProfileName(
      cachedProfile?.fullName,
      fallback: null,
    );
    if (cachedName == null) rethrow;
    return [cachedName];
  }
});

Future<String?> _fallbackAssignedTo(
  Ref ref,
  AppDatabase db,
  String workOrderId,
) async {
  try {
    final workOrder = await ref.read(workOrderByIdProvider(workOrderId).future);
    final assignedTo = workOrder?.assignedTo;
    if (assignedTo != null) return assignedTo;
  } catch (_) {
    // Fall back to the local row below.
  }

  final localRow = await db.workOrdersDao.getById(workOrderId);
  return localRow?.assignedTo;
}
