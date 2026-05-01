import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/db/daos/assets_dao.dart';
import 'package:vortice_app/db/daos/checklists_dao.dart';
import 'package:vortice_app/db/daos/invoices_dao.dart';
import 'package:vortice_app/db/daos/parts_dao.dart';
import 'package:vortice_app/db/daos/service_reports_dao.dart';
import 'package:vortice_app/db/daos/work_orders_dao.dart';

part 'database.g.dart';

// ── Table definitions ──────────────────────────────────────────────────────

class ProfilesTable extends Table {
  @override
  String get tableName => 'profiles';

  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get fullName => text()();
  TextColumn get role => text().withDefault(const Constant('employee'))();
  TextColumn get phone => text().nullable()();
  TextColumn get preferredLanguage => text().withDefault(const Constant('en'))();
  TextColumn get orgCodeUsed => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AssetsTable extends Table {
  @override
  String get tableName => 'assets';

  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get assetTypeId => text()();
  TextColumn get name => text()();
  TextColumn get make => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get telemetryEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get telemetrySource => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AssetEnginesTable extends Table {
  @override
  String get tableName => 'asset_engines';

  TextColumn get id => text()();
  TextColumn get assetId => text().references(AssetsTable, #id)();
  TextColumn get label => text()();
  TextColumn get kind => text().withDefault(const Constant('engine'))();
  TextColumn get make => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  RealColumn get currentHours => real().withDefault(const Constant(0))();
  TextColumn get telemetryChannel => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkOrdersTable extends Table {
  @override
  String get tableName => 'work_orders';

  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get engineId => text().nullable()();
  TextColumn get clientId => text()();
  TextColumn get assignedTo => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get checklistTemplateId => text().nullable()();
  IntColumn get checklistTemplateVersion => integer().nullable()();
  TextColumn get jobType => text().withDefault(const Constant('repair'))();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  RealColumn get hoursAtStart => real().nullable()();
  RealColumn get hoursAtEnd => real().nullable()();
  RealColumn get labourHours => real().nullable()();
  RealColumn get billableRate => real().nullable()();
  RealColumn get wageRate => real().nullable()();
  TextColumn get notesInternal => text().nullable()();
  TextColumn get onHoldReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChecklistTemplatesTable extends Table {
  @override
  String get tableName => 'checklist_templates';

  TextColumn get id => text()();
  TextColumn get assetTypeId => text().nullable()();
  TextColumn get checklistType => text().withDefault(const Constant('pm'))();
  IntColumn get intervalHours => integer().nullable()();
  TextColumn get intervalLabel => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get sourceDocId => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChecklistItemsTable extends Table {
  @override
  String get tableName => 'checklist_items';

  TextColumn get id => text()();
  TextColumn get templateId =>
      text().references(ChecklistTemplatesTable, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get descriptionEn => text()();
  TextColumn get descriptionEs => text().nullable()();
  TextColumn get category => text().nullable()();
  BoolColumn get requiresPhoto => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChecklistResponsesTable extends Table {
  @override
  String get tableName => 'checklist_responses';

  TextColumn get id => text()();
  TextColumn get workOrderId => text()();
  TextColumn get checklistItemId => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get completedBy => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ServiceReportsTable extends Table {
  @override
  String get tableName => 'service_reports';

  TextColumn get id => text()();
  TextColumn get workOrderId => text()();
  TextColumn get complaint => text().nullable()();
  TextColumn get cause => text().nullable()();
  TextColumn get correction => text().nullable()();
  TextColumn get collateral => text().nullable()();
  TextColumn get comments => text().nullable()();
  TextColumn get techSignatureUrl => text().nullable()();
  DateTimeColumn get signedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PartsTable extends Table {
  @override
  String get tableName => 'parts';

  TextColumn get id => text()();
  TextColumn get workOrderId => text()();
  TextColumn get description => text()();
  TextColumn get partNumber => text().nullable()();
  TextColumn get supplier => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  RealColumn get unitCost => real()();
  RealColumn get markupPct => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get loggedBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class InvoicesTable extends Table {
  @override
  String get tableName => 'invoices';

  TextColumn get id => text()();
  TextColumn get workOrderId => text()();
  TextColumn get clientId => text()();
  TextColumn get invoiceNumber => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  RealColumn get labourHours => real().nullable()();
  RealColumn get billableRateUsd => real().nullable()();
  RealColumn get labourTotalUsd => real().nullable()();
  RealColumn get partsTotalUsd => real().nullable()();
  RealColumn get consumablesTotalUsd => real().nullable()();
  RealColumn get subtotalUsd => real().nullable()();
  RealColumn get ivaPct => real().withDefault(const Constant(16.0))();
  RealColumn get ivaTotalUsd => real().nullable()();
  RealColumn get totalUsd => real().nullable()();
  RealColumn get exchangeRate => real().nullable()();
  RealColumn get totalMxn => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get pdfUrl => text().nullable()();
  TextColumn get xlsxUrl => text().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get paidAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Database ───────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    ProfilesTable,
    AssetsTable,
    AssetEnginesTable,
    WorkOrdersTable,
    ChecklistTemplatesTable,
    ChecklistItemsTable,
    ChecklistResponsesTable,
    ServiceReportsTable,
    PartsTable,
    InvoicesTable,
  ],
  daos: [
    AssetsDao,
    WorkOrdersDao,
    ChecklistsDao,
    ServiceReportsDao,
    PartsDao,
    InvoicesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'vortice_db'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // Dev-only: drop and recreate all tables on any schema change
      for (final table in allTables) {
        await m.deleteTable(table.actualTableName);
      }
      await m.createAll();
    },
  );
}

// ── Provider ───────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
