import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'assets_dao.g.dart';

@DriftAccessor(tables: [AssetsTable])
class AssetsDao extends DatabaseAccessor<AppDatabase> with _$AssetsDaoMixin {
  AssetsDao(super.db);

  Stream<List<AssetsTableData>> watchAll() =>
      (select(assetsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<AssetsTableData>> getAll() =>
      (select(assetsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<AssetsTableData?> getById(String id) =>
      (select(assetsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(AssetsTableCompanion entry) =>
      into(assetsTable).insertOnConflictUpdate(entry);

  Future<void> upsertAll(List<AssetsTableCompanion> entries) =>
      transaction(() async {
        await batch((b) => b.insertAllOnConflictUpdate(assetsTable, entries));
      });

  Future<int> deleteById(String id) =>
      (delete(assetsTable)..where((t) => t.id.equals(id))).go();
}
