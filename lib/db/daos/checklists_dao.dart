import 'package:drift/drift.dart';
import 'package:vortice_app/db/database.dart';

part 'checklists_dao.g.dart';

@DriftAccessor(tables: [
  ChecklistTemplatesTable,
  ChecklistItemsTable,
  ChecklistResponsesTable,
])
class ChecklistsDao extends DatabaseAccessor<AppDatabase>
    with _$ChecklistsDaoMixin {
  ChecklistsDao(super.db);

  // ── Templates ──────────────────────────────────────────────────────────

  Future<List<ChecklistTemplatesTableData>> getAllTemplates() =>
      (select(checklistTemplatesTable)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<void> upsertTemplate(ChecklistTemplatesTableCompanion entry) =>
      into(checklistTemplatesTable).insertOnConflictUpdate(entry);

  // ── Items ──────────────────────────────────────────────────────────────

  Future<List<ChecklistItemsTableData>> getItemsForTemplate(
          String templateId) =>
      (select(checklistItemsTable)
            ..where((t) => t.templateId.equals(templateId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<void> upsertItem(ChecklistItemsTableCompanion entry) =>
      into(checklistItemsTable).insertOnConflictUpdate(entry);

  // ── Responses ──────────────────────────────────────────────────────────

  Stream<List<ChecklistResponsesTableData>> watchResponsesForWorkOrder(
          String workOrderId) =>
      (select(checklistResponsesTable)
            ..where((t) => t.workOrderId.equals(workOrderId)))
          .watch();

  Future<List<ChecklistResponsesTableData>> getResponsesForWorkOrder(
          String workOrderId) =>
      (select(checklistResponsesTable)
            ..where((t) => t.workOrderId.equals(workOrderId)))
          .get();

  Future<void> upsertResponse(ChecklistResponsesTableCompanion entry) =>
      into(checklistResponsesTable).insertOnConflictUpdate(entry);

  Future<int> deleteResponsesForWorkOrder(String workOrderId) =>
      (delete(checklistResponsesTable)
            ..where((t) => t.workOrderId.equals(workOrderId)))
          .go();
}
