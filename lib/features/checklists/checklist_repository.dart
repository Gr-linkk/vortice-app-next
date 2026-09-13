import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:vortice_app/core/account_storage.dart';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/checklists/checklist_repository_support.dart';
import 'package:vortice_app/features/checklists/checklist_submission_support.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

final checklistRepositoryProvider = Provider<ChecklistRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ChecklistRepository(db);
});

class LocalChecklistPendingException implements Exception {
  const LocalChecklistPendingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChecklistRepository {
  ChecklistRepository(this._db);

  final AppDatabase _db;
  void _checkAccount() {
    if (_db.accountId != null &&
        !_db.belongsTo(supabase.auth.currentUser?.id)) {
      throw const AccountChangedException();
    }
  }

  AccountJsonCache get _cache => AccountJsonCache(
    supabase.auth.currentUser!.id,
    () => supabase.auth.currentUser?.id,
  );

  Future<List<ChecklistTemplate>> listTemplates() async {
    _checkAccount();
    final remote = await _cache.readThrough(
      'checklist_templates',
      () => supabase
          .from(AppConstants.tChecklistTemplates)
          .select()
          .order('name')
          .timeout(const Duration(seconds: 6)),
    );
    return (remote as List)
        .map((e) => ChecklistTemplate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ChecklistItem>> listItemsForTemplate(String templateId) async {
    _checkAccount();
    final remote = await _cache.readThrough(
      'checklist_items:$templateId',
      () => supabase
          .from(AppConstants.tChecklistItems)
          .select()
          .eq('template_id', templateId)
          .order('sort_order', ascending: true)
          .timeout(const Duration(seconds: 6)),
    );
    return (remote as List)
        .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e)))
        .where(isAllowedChecklistItem)
        .toList();
  }

  Future<void> cacheSnapshot(WorkOrderChecklistSnapshot snapshot) async {
    _checkAccount();
    // A frozen job must not replace live publication scope or reactivate a
    // retired procedure in the offline library.
    final cached = await _db.checklistsDao.getAllTemplates();
    if (!cached.any((t) => t.id == snapshot.asTemplate().id)) {
      await _db.checklistsDao.upsertTemplate(
        _templateToCompanion(snapshot.asTemplate().copyWith(isActive: false)),
      );
    }
    await _db.checklistsDao.upsertItems(
      snapshot.items.map(_itemToCompanion).toList(),
    );
  }

  Future<List<ChecklistResponse>> listResponsesForWorkOrder(
    String workOrderId,
  ) async {
    _checkAccount();
    final cached = (await _db.checklistsDao.getResponsesForWorkOrder(
      workOrderId,
    )).map(_responseFromRow).toList();

    try {
      final remote = await _cache.readThrough(
        'checklist_responses:$workOrderId',
        () => supabase
            .from(AppConstants.tChecklistResponses)
            .select()
            .eq('work_order_id', workOrderId)
            .timeout(const Duration(seconds: 6)),
      );
      _checkAccount();

      final responses = (remote as List)
          .map((e) => ChecklistResponse.fromJson(e as Map<String, dynamic>))
          .toList();
      final localUnsyncedByItem = {
        for (final response in cached)
          if (response.syncStatus != SyncStatusValues.synced)
            response.checklistItemId: response,
      };

      await _db.checklistsDao.upsertResponses(
        remoteChecklistResponsesSafeToUpsert(
              remoteResponses: responses,
              localUnsyncedByItem: localUnsyncedByItem,
            )
            .map(
              (response) => _responseToCompanion(
                response,
                syncStatus: SyncStatusValues.synced,
                lastSyncedAt: DateTime.now(),
                lastError: null,
              ),
            )
            .toList(),
      );

      return mergeResponsesPreferUnsynced(
        remoteResponses: responses,
        localResponses: cached,
      );
    } catch (error) {
      _checkAccount();
      if (!isConnectionFailure(error) ||
          !_db.belongsTo(supabase.auth.currentUser?.id)) {
        rethrow;
      }
      final unsent = cached
          .where((r) => r.syncStatus != SyncStatusValues.synced)
          .toList();
      if (unsent.isNotEmpty) return unsent;
      rethrow;
    }
  }

  Future<bool> hasResponsesForWorkOrder(String workOrderId) async =>
      (await listResponsesForWorkOrder(workOrderId)).isNotEmpty;

  Future<void> submitBatchResponses({
    required String workOrderId,
    required String completedBy,
    required Map<String, String?> responses,
    Map<String, String>? notes,
    Map<String, String?>? photoUrls,
    String? holdForSyncReason,
  }) async {
    _checkAccount();
    final now = DateTime.now();
    final answered = responses.entries.where((e) => e.value != null).toList();
    if (answered.isEmpty) return;

    final rows = <Map<String, dynamic>>[];
    final localResponses = <ChecklistResponse>[];
    final localEntries = <ChecklistResponsesTableCompanion>[];
    final existingByItem = <String, ChecklistResponsesTableData?>{};

    for (final entry in answered) {
      final existing = await _db.checklistsDao.getResponseForWorkOrderItem(
        workOrderId,
        entry.key,
      );
      existingByItem[entry.key] = existing;
      final response = buildChecklistResponse(
        id: existing?.id ?? _uuidV4(),
        workOrderId: workOrderId,
        checklistItemId: entry.key,
        completedBy: completedBy,
        status: entry.value!,
        notes: notes?[entry.key],
        photoUrl: photoUrls?[entry.key],
        completedAt: now,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        syncStatus: SyncStatusValues.synced,
        lastSyncedAt: now,
      );
      rows.add(checklistResponseToRemoteRow(response));
      localResponses.add(response);
      localEntries.add(
        _responseToCompanion(
          response,
          syncStatus: SyncStatusValues.synced,
          updatedAt: now,
          lastSyncedAt: now,
          lastError: null,
        ),
      );
    }

    final pendingEntries = <ChecklistResponsesTableCompanion>[];
    for (var i = 0; i < answered.length; i++) {
      final entry = answered[i];
      final existing = existingByItem[entry.key];
      final response = localResponses[i].copyWith(
        syncStatus: pendingChecklistSyncStatus(hasExisting: existing != null),
        lastSyncedAt: existing?.lastSyncedAt,
      );
      pendingEntries.add(
        _responseToCompanion(
          response,
          syncStatus: response.syncStatus,
          updatedAt: now,
          lastSyncedAt: existing?.lastSyncedAt,
          lastError: null,
        ),
      );
    }

    // Save locally before touching the network. This makes airplane-mode field
    // saves visible immediately instead of waiting for a long HTTP timeout.
    await _db.checklistsDao.upsertResponses(pendingEntries);

    try {
      await supabase
          .from(AppConstants.tChecklistResponses)
          .upsert(rows, onConflict: 'id')
          .timeout(const Duration(seconds: 4));
      await _db.checklistsDao.upsertResponses(localEntries);
    } on TimeoutException catch (error) {
      await _markPendingResponsesWithError(pendingEntries, error);
      throw LocalChecklistPendingException(
        ChecklistSubmissionSupport.pendingSyncMessage(intentionalOffline: true),
      );
    } catch (error) {
      await _markPendingResponsesWithError(pendingEntries, error);
      if (ChecklistSubmissionSupport.isPermissionSyncError(error)) {
        rethrow;
      }
      if (ChecklistSubmissionSupport.isTransientSyncError(error)) {
        throw LocalChecklistPendingException(
          ChecklistSubmissionSupport.pendingSyncMessage(
            intentionalOffline: false,
          ),
        );
      }
      rethrow;
    }
  }

  Future<int> syncPendingResponsesForWorkOrder(String workOrderId) async {
    final cached =
        (await _db.checklistsDao.getResponsesForWorkOrder(workOrderId))
            .map(_responseFromRow)
            .where((response) => response.syncStatus != SyncStatusValues.synced)
            .toList();
    if (cached.isEmpty) return 0;

    final rows = cached.map(checklistResponseToRemoteRow).toList();
    final now = DateTime.now();

    try {
      await supabase
          .from(AppConstants.tChecklistResponses)
          .upsert(rows, onConflict: 'id')
          .timeout(const Duration(seconds: 4));
      await _db.checklistsDao.upsertResponses(
        cached
            .map(
              (response) => _responseToCompanion(
                response,
                syncStatus: SyncStatusValues.synced,
                updatedAt: now,
                lastSyncedAt: now,
                lastError: null,
              ),
            )
            .toList(),
      );
      return cached.length;
    } catch (error) {
      await _db.checklistsDao.upsertResponses(
        cached
            .map(
              (response) => _responseToCompanion(
                response,
                syncStatus: response.syncStatus,
                updatedAt: now,
                lastSyncedAt: response.lastSyncedAt,
                lastError: error.toString(),
              ),
            )
            .toList(),
      );
      if (ChecklistSubmissionSupport.isPermissionSyncError(error)) {
        rethrow;
      }
      if (ChecklistSubmissionSupport.isTransientSyncError(error)) {
        throw LocalChecklistPendingException(
          ChecklistSubmissionSupport.pendingSyncMessage(
            intentionalOffline: false,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _markPendingResponsesWithError(
    List<ChecklistResponsesTableCompanion> entries,
    Object error,
  ) async {
    await _db.checklistsDao.upsertResponses(
      entries
          .map((entry) => entry.copyWith(lastError: Value(error.toString())))
          .toList(),
    );
  }
}

ChecklistTemplatesTableCompanion _templateToCompanion(
  ChecklistTemplate template,
) => ChecklistTemplatesTableCompanion(
  id: Value(template.id),
  assetTypeId: Value(template.assetTypeId),
  checklistType: Value(template.checklistType),
  intervalHours: Value(template.intervalHours),
  intervalLabel: Value(template.intervalLabel),
  name: Value(template.name),
  description: Value(template.description),
  version: Value(template.version),
  isActive: Value(template.isActive),
  sourceDocId: Value(template.sourceDocId),
  scopeJson: Value(
    jsonEncode({
      'procedure_id': template.procedureId,
      'client_id': template.clientId,
      'scope_asset_id': template.scopeAssetId,
      'scope_engine_id': template.scopeEngineId,
    }),
  ),
  createdBy: Value(template.createdBy),
  createdAt: Value(template.createdAt),
  updatedAt: Value(template.updatedAt),
);

ChecklistItemsTableCompanion _itemToCompanion(ChecklistItem item) =>
    ChecklistItemsTableCompanion(
      id: Value(item.id),
      templateId: Value(item.templateId),
      sortOrder: Value(item.sortOrder),
      descriptionEn: Value(item.descriptionEn),
      descriptionEs: Value(item.descriptionEs),
      category: Value(item.category),
      definitionJson: Value(jsonEncode(item.definition)),
      requiresPhoto: Value(item.requiresPhoto),
      createdAt: Value(item.createdAt),
    );

ChecklistResponse _responseFromRow(ChecklistResponsesTableData row) =>
    ChecklistResponse(
      id: row.id,
      workOrderId: row.workOrderId,
      checklistItemId: row.checklistItemId,
      completed: row.completed,
      notes: row.notes,
      photoUrl: row.photoUrl,
      responseStatus: row.responseStatus,
      completedBy: row.completedBy,
      completedAt: row.completedAt,
      createdAt: row.createdAt,
      syncStatus: row.syncStatus,
      updatedAt: row.updatedAt,
      lastSyncedAt: row.lastSyncedAt,
      lastError: row.lastError,
    );

ChecklistResponsesTableCompanion _responseToCompanion(
  ChecklistResponse response, {
  required String syncStatus,
  DateTime? updatedAt,
  DateTime? lastSyncedAt,
  String? lastError,
}) => ChecklistResponsesTableCompanion(
  id: Value(response.id),
  workOrderId: Value(response.workOrderId),
  checklistItemId: Value(response.checklistItemId),
  completed: Value(response.completed),
  notes: Value(response.notes),
  photoUrl: Value(response.photoUrl),
  responseStatus: Value(response.responseStatus),
  completedBy: Value(response.completedBy),
  completedAt: Value(response.completedAt),
  createdAt: Value(response.createdAt),
  syncStatus: Value(syncStatus),
  updatedAt: Value(updatedAt ?? response.updatedAt),
  lastSyncedAt: Value(lastSyncedAt ?? response.lastSyncedAt),
  lastError: Value(lastError),
);

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
