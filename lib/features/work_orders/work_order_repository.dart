import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

final workOrderRepositoryProvider = Provider<WorkOrderRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final modern =
      ref.watch(profileProvider).valueOrNull?.membershipManaged == true;
  return WorkOrderRepository(db, organizationMembership: modern);
});

class WorkOrderRepository {
  WorkOrderRepository(
    this._db, {
    SupabaseClient? client,
    this.organizationMembership = false,
  }) : _client = client ?? supabase;
  final AppDatabase _db;
  final SupabaseClient _client;
  final bool organizationMembership;
  AccountJsonCache get _cache => AccountJsonCache(
    _db.accountId ?? 'signed_out',
    () => _client.auth.currentUser?.id,
  );
  void _check() {
    if (!_db.belongsTo(_client.auth.currentUser?.id)) {
      throw const AccountChangedException();
    }
  }

  Future<List<WorkOrder>> listWorkOrders() async {
    _check();
    final raw = await _cache.readThrough(
      'provider_work_orders',
      () async {
        final rows = <Map<String, dynamic>>[];
        for (var offset = 0; ; offset += 500) {
          final page = await _client
              .from(AppConstants.tWorkOrders)
              .select()
              .order('id')
              .range(offset, offset + 499)
              .timeout(const Duration(seconds: 6));
          _check();
          rows.addAll(page);
          if (page.length < 500) break;
        }
        if (organizationMembership) {
          final shared =
              await _client
                      .rpc('organization_work_orders')
                      .timeout(const Duration(seconds: 6))
                  as List;
          final byId = {for (final row in rows) row['id'] as String: row};
          for (final raw in shared) {
            final row = Map<String, dynamic>.from(raw as Map);
            byId[row['id'] as String] = row;
          }
          rows
            ..clear()
            ..addAll(byId.values);
        }
        final orders = rows.map(WorkOrder.fromJson).toList();
        await _db.transaction(() async {
          final ids = orders.map((o) => o.id).toSet();
          for (final old in await _db.workOrdersDao.getAll()) {
            if (!ids.contains(old.id)) {
              await _db.workOrdersDao.deleteById(old.id);
            }
          }
          await _db.workOrdersDao.upsertAll(orders.map(_toCompanion).toList());
        });
        return rows;
      },
      derivedValues: (data) => {
        for (final row in data as List) 'provider_work_order:${row['id']}': row,
      },
      replaceDerivedPrefix: 'provider_work_order:',
    );
    final orders = (raw as List)
        .map((r) => WorkOrder.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    orders.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return orders;
  }

  Future<WorkOrder?> getWorkOrderById(String id) async {
    _check();
    final data = await _cache.readThrough('provider_work_order:$id', () async {
      var row = await _client
          .from(AppConstants.tWorkOrders)
          .select()
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      if (row == null && organizationMembership) {
        // Customer rows are projected by the server, so internal notes and
        // provider rates never enter the customer's cache.
        final accessible =
            await _client
                    .rpc('organization_work_orders')
                    .timeout(const Duration(seconds: 6))
                as List;
        for (final candidate in accessible.whereType<Map>()) {
          if (candidate['id'] == id) row = Map<String, dynamic>.from(candidate);
        }
      }
      _check();
      if (row == null) {
        await _db.workOrdersDao.deleteById(id);
      } else {
        await _db.workOrdersDao.upsert(_toCompanion(WorkOrder.fromJson(row)));
      }
      return row;
    });
    return data == null
        ? null
        : WorkOrder.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

WorkOrdersTableCompanion _toCompanion(WorkOrder workOrder) =>
    WorkOrdersTableCompanion(
      id: Value(workOrder.id),
      meterUnit: Value(workOrder.meterUnit),
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
