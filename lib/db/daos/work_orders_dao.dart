import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'work_orders_dao.g.dart';

@DriftAccessor(tables: [WorkOrdersTable])
class WorkOrdersDao extends DatabaseAccessor<AppDatabase>
    with _$WorkOrdersDaoMixin {
  WorkOrdersDao(super.db);

  Stream<List<WorkOrdersTableData>> watchAll() =>
      (select(workOrdersTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<List<WorkOrdersTableData>> getAll() =>
      (select(workOrdersTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<WorkOrdersTableData>> getByStatus(String status) =>
      (select(workOrdersTable)..where((t) => t.status.equals(status))).get();

  Future<List<WorkOrdersTableData>> getAssignedTo(String userId) =>
      (select(workOrdersTable)..where((t) => t.assignedTo.equals(userId))).get();

  Future<WorkOrdersTableData?> getById(String id) =>
      (select(workOrdersTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsert(WorkOrdersTableCompanion entry) =>
      into(workOrdersTable).insertOnConflictUpdate(entry);

  Future<void> upsertAll(List<WorkOrdersTableCompanion> entries) =>
      transaction(() async {
        await batch((b) =>
            b.insertAllOnConflictUpdate(workOrdersTable, entries));
      });

  Future<int> deleteById(String id) =>
      (delete(workOrdersTable)..where((t) => t.id.equals(id))).go();
}
