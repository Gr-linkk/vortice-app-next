import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/models/work_order.dart';

final workOrderRepositoryProvider = Provider<WorkOrderRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return WorkOrderRepository(db);
});

class WorkOrderRepository {
  WorkOrderRepository(this._db);

  final AppDatabase _db;

  Future<List<WorkOrder>> listWorkOrders() async {
    final cached = (await _db.workOrdersDao.getAll()).map(_fromRow).toList();

    try {
      final remote = await supabase
          .from(AppConstants.tWorkOrders)
          .select()
          .order('created_at', ascending: false);

      final orders = (remote as List)
          .map((e) => WorkOrder.fromJson(e as Map<String, dynamic>))
          .toList();

      if (orders.isNotEmpty) {
        await _db.workOrdersDao.upsertAll(orders.map(_toCompanion).toList());
      }

      return orders;
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<WorkOrder?> getWorkOrderById(String id) async {
    final cachedRow = await _db.workOrdersDao.getById(id);
    final cached = cachedRow == null ? null : _fromRow(cachedRow);

    try {
      final data = await supabase
          .from(AppConstants.tWorkOrders)
          .select()
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;

      final workOrder = WorkOrder.fromJson(data);
      await _db.workOrdersDao.upsert(_toCompanion(workOrder));
      return workOrder;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }
}

WorkOrder _fromRow(WorkOrdersTableData row) => WorkOrder(
      id: row.id,
      assetId: row.assetId,
      engineId: row.engineId,
      clientId: row.clientId,
      assignedTo: row.assignedTo,
      createdBy: row.createdBy,
      checklistTemplateId: row.checklistTemplateId,
      checklistTemplateVersion: row.checklistTemplateVersion,
      jobType: _parseJobType(row.jobType),
      title: row.title,
      description: row.description,
      status: _parseStatus(row.status),
      scheduledDate: row.scheduledDate,
      startedAt: row.startedAt,
      completedAt: row.completedAt,
      hoursAtStart: row.hoursAtStart,
      hoursAtEnd: row.hoursAtEnd,
      labourHours: row.labourHours,
      billableRate: row.billableRate,
      wageRate: row.wageRate,
      notesInternal: row.notesInternal,
      onHoldReason: row.onHoldReason,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );

WorkOrdersTableCompanion _toCompanion(WorkOrder workOrder) =>
    WorkOrdersTableCompanion(
      id: Value(workOrder.id),
      assetId: Value(workOrder.assetId),
      engineId: Value(workOrder.engineId),
      clientId: Value(workOrder.clientId),
      assignedTo: Value(workOrder.assignedTo),
      createdBy: Value(workOrder.createdBy),
      checklistTemplateId: Value(workOrder.checklistTemplateId),
      checklistTemplateVersion: Value(workOrder.checklistTemplateVersion),
      jobType: Value(workOrder.jobType.dbValue),
      title: Value(workOrder.title),
      description: Value(workOrder.description),
      status: Value(workOrder.status.dbValue),
      scheduledDate: Value(workOrder.scheduledDate),
      startedAt: Value(workOrder.startedAt),
      completedAt: Value(workOrder.completedAt),
      hoursAtStart: Value(workOrder.hoursAtStart),
      hoursAtEnd: Value(workOrder.hoursAtEnd),
      labourHours: Value(workOrder.labourHours),
      billableRate: Value(workOrder.billableRate),
      wageRate: Value(workOrder.wageRate),
      notesInternal: Value(workOrder.notesInternal),
      onHoldReason: Value(workOrder.onHoldReason),
      createdAt: Value(workOrder.createdAt),
      updatedAt: Value(workOrder.updatedAt),
    );

WorkOrderJobType _parseJobType(String value) {
  for (final jobType in WorkOrderJobType.values) {
    if (jobType.dbValue == value) return jobType;
  }
  return WorkOrderJobType.repair;
}

WorkOrderStatus _parseStatus(String value) {
  for (final status in WorkOrderStatus.values) {
    if (status.dbValue == value) return status;
  }
  return WorkOrderStatus.draft;
}
