import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'invoices_dao.g.dart';

@DriftAccessor(tables: [InvoicesTable])
class InvoicesDao extends DatabaseAccessor<AppDatabase>
    with _$InvoicesDaoMixin {
  InvoicesDao(super.db);

  Future<List<InvoicesTableData>> getAll() =>
      (select(invoicesTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<InvoicesTableData>> watchAll() =>
      (select(invoicesTable)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<InvoicesTableData?> getById(String id) =>
      (select(invoicesTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<InvoicesTableData>> getByStatus(String status) =>
      (select(invoicesTable)..where((t) => t.status.equals(status))).get();

  Future<void> upsert(InvoicesTableCompanion entry) =>
      into(invoicesTable).insertOnConflictUpdate(entry);

  Future<int> deleteById(String id) =>
      (delete(invoicesTable)..where((t) => t.id.equals(id))).go();
}
