import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'service_reports_dao.g.dart';

@DriftAccessor(tables: [ServiceReportsTable])
class ServiceReportsDao extends DatabaseAccessor<AppDatabase>
    with _$ServiceReportsDaoMixin {
  ServiceReportsDao(super.db);

  Future<List<ServiceReportsTableData>> getAll() =>
      (select(serviceReportsTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<ServiceReportsTableData?> getById(String id) =>
      (select(serviceReportsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<ServiceReportsTableData?> getByWorkOrder(String workOrderId) =>
      (select(serviceReportsTable)
            ..where((t) => t.workOrderId.equals(workOrderId)))
          .getSingleOrNull();

  Future<void> upsert(ServiceReportsTableCompanion entry) =>
      into(serviceReportsTable).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(serviceReportsTable)..where((t) => t.id.equals(id))).go();
}
