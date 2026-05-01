import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'parts_dao.g.dart';

@DriftAccessor(tables: [PartsTable])
class PartsDao extends DatabaseAccessor<AppDatabase> with _$PartsDaoMixin {
  PartsDao(super.db);

  Future<List<PartsTableData>> getAll() =>
      (select(partsTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<PartsTableData>> getByWorkOrder(String workOrderId) =>
      (select(partsTable)..where((t) => t.workOrderId.equals(workOrderId)))
          .get();

  Future<void> upsert(PartsTableCompanion entry) =>
      into(partsTable).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(partsTable)..where((t) => t.id.equals(id))).go();
}
