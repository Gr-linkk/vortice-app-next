import 'package:drift/drift.dart' show Value;
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/work_orders/work_order_support.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/work_order.dart';

const profileSelectColumns =
    'id, email, full_name, role, phone, preferred_language, org_code_used, created_at, updated_at';

Future<ProfilesTableData?> cachedProfileById(
  AppDatabase db,
  String profileId,
) {
  return (db.select(db.profilesTable)..where((t) => t.id.equals(profileId)))
      .getSingleOrNull();
}

Future<void> upsertRemoteProfile(
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
          createdAt: Value(parseDateTime(row['created_at'])),
          updatedAt: Value(parseDateTime(row['updated_at'])),
        ),
      );
}

Future<void> upsertRemoteProfiles(
  AppDatabase db,
  Iterable<Map<String, dynamic>> rows,
) async {
  for (final row in rows) {
    await upsertRemoteProfile(db, row);
  }
}

AssetsTableCompanion assetToCompanion(Asset asset) => AssetsTableCompanion(
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

Future<String?> fallbackAssignedTo(
  AppDatabase db,
  Future<WorkOrder?> Function() loadWorkOrder,
  String workOrderId,
) async {
  try {
    final workOrder = await loadWorkOrder();
    final assignedTo = workOrder?.assignedTo;
    if (assignedTo != null) return assignedTo;
  } catch (_) {
    // Fall back to the local row below.
  }

  final localRow = await db.workOrdersDao.getById(workOrderId);
  return localRow?.assignedTo;
}
