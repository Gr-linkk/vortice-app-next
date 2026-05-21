import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/sync/sync_status.dart';

part 'service_reports_dao.g.dart';

@DriftAccessor(tables: [ServiceReportsTable, WorkOrdersTable])
class ServiceReportsDao extends DatabaseAccessor<AppDatabase>
    with _$ServiceReportsDaoMixin {
  ServiceReportsDao(super.db);

  Future<List<ServiceReportsTableData>> getAll() => (select(serviceReportsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .get();

  Future<ServiceReportsTableData?> getById(String id) =>
      (select(serviceReportsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<ServiceReportsTableData>> listByWorkOrder(String workOrderId) =>
      (select(serviceReportsTable)
            ..where((t) => t.workOrderId.equals(workOrderId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<ServiceReportsTableData>> listByAsset(String assetId) async {
    final query = select(serviceReportsTable).join([
      innerJoin(
        workOrdersTable,
        workOrdersTable.id.equalsExp(serviceReportsTable.workOrderId),
      ),
    ])
      ..where(workOrdersTable.assetId.equals(assetId))
      ..orderBy([OrderingTerm.desc(serviceReportsTable.createdAt)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(serviceReportsTable)).toList();
  }

  Future<ServiceReportsTableData?> getLatestByWorkOrder(String workOrderId) =>
      (select(serviceReportsTable)
            ..where((t) => t.workOrderId.equals(workOrderId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<List<ServiceReportsTableData>> listPendingSync() =>
      (select(serviceReportsTable)
            ..where((t) => t.syncStatus.isNotIn([SyncStatusValues.synced]))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<void> upsertAll(List<ServiceReportsTableCompanion> entries) async {
    await batch(
        (b) => b.insertAllOnConflictUpdate(serviceReportsTable, entries));
  }

  Future<void> upsert(ServiceReportsTableCompanion entry) =>
      into(serviceReportsTable).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(serviceReportsTable)..where((t) => t.id.equals(id))).go();
}
