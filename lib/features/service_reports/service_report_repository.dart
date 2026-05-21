import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/models/service_report.dart';
import 'package:vortice_app/sync/sync_status.dart';

final serviceReportRepositoryProvider =
    Provider<ServiceReportRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ServiceReportRepository(db);
});

class LocalServiceReportPendingException implements Exception {
  const LocalServiceReportPendingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServiceReportSubmitResult {
  const ServiceReportSubmitResult({
    required this.reportId,
    required this.synced,
  });

  final String reportId;
  final bool synced;
}

class ServiceReportRepository {
  ServiceReportRepository(this._db);

  final AppDatabase _db;

  Future<List<ServiceReport>> listAll() async {
    await syncPendingServiceReports();
    final cached =
        (await _db.serviceReportsDao.getAll()).map(_fromRow).toList();
    try {
      final remote = await supabase
          .from(AppConstants.tServiceReports)
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      return _cacheAndMergeRemote(remote as List, cached);
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<ServiceReport?> getById(String reportId) async {
    await syncPendingServiceReports(reportId: reportId);
    final cachedRow = await _db.serviceReportsDao.getById(reportId);
    final cached = cachedRow == null ? null : _fromRow(cachedRow);
    try {
      final remote = await supabase
          .from(AppConstants.tServiceReports)
          .select()
          .eq('id', reportId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      if (remote == null) return cached;
      final report = ServiceReport.fromJson(remote);
      if (cached?.syncStatus != SyncStatusValues.synced) {
        return cached;
      }
      await _db.serviceReportsDao.upsert(
        _toCompanion(
          report,
          syncStatus: SyncStatusValues.synced,
          lastSyncedAt: DateTime.now(),
          lastError: null,
        ),
      );
      return report.copyWith(
        syncStatus: SyncStatusValues.synced,
        lastSyncedAt: DateTime.now(),
        lastError: null,
      );
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<ServiceReport>> listByWorkOrder(String workOrderId) async {
    await syncPendingServiceReports(workOrderId: workOrderId);
    final cached = (await _db.serviceReportsDao.listByWorkOrder(workOrderId))
        .map(_fromRow)
        .toList();
    try {
      final remote = await supabase
          .from(AppConstants.tServiceReports)
          .select()
          .eq('work_order_id', workOrderId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      return _cacheAndMergeRemote(remote as List, cached);
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<ServiceReport>> listForAsset(String assetId) async {
    await syncPendingServiceReports();
    final cached = (await _db.serviceReportsDao.listByAsset(assetId))
        .map(_fromRow)
        .toList();
    try {
      final remote = await supabase
          .from(AppConstants.tServiceReports)
          .select('*, work_orders!inner(asset_id)')
          .eq('work_orders.asset_id', assetId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 4));
      return _cacheAndMergeRemote(remote as List, cached);
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<ServiceReportSubmitResult> createLocalFirst({
    String? reportId,
    required String workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    String? techSignatureUrl,
  }) async {
    final now = DateTime.now();
    final id = reportId ?? _uuidV4();
    final report = ServiceReport(
      id: id,
      workOrderId: workOrderId,
      complaint: complaint,
      cause: cause,
      correction: correction,
      collateral: collateral,
      comments: comments,
      techSignatureUrl: techSignatureUrl,
      signedAt: techSignatureUrl == null ? null : now,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatusValues.pendingCreate,
      lastSyncedAt: null,
      lastError: null,
    );

    await _db.serviceReportsDao.upsert(
      _toCompanion(
        report,
        syncStatus: SyncStatusValues.pendingCreate,
        updatedAt: now,
        lastSyncedAt: null,
        lastError: null,
      ),
    );

    try {
      await supabase
          .from(AppConstants.tServiceReports)
          .upsert(_toRemoteRow(report), onConflict: 'id')
          .timeout(const Duration(seconds: 4));
      await _db.serviceReportsDao.upsert(
        _toCompanion(
          report.copyWith(syncStatus: SyncStatusValues.synced),
          syncStatus: SyncStatusValues.synced,
          updatedAt: now,
          lastSyncedAt: DateTime.now(),
          lastError: null,
        ),
      );
      return ServiceReportSubmitResult(reportId: id, synced: true);
    } on TimeoutException catch (error) {
      await markPending(reportId: id, error: error);
      return ServiceReportSubmitResult(reportId: id, synced: false);
    } catch (error) {
      await markPending(reportId: id, error: error);
      return ServiceReportSubmitResult(reportId: id, synced: false);
    }
  }

  Future<void> updateLocalAndRemote({
    required String reportId,
    required String workOrderId,
    String? complaint,
    String? cause,
    String? correction,
    String? collateral,
    String? comments,
    String? techSignatureUrl,
  }) async {
    final existing = await getById(reportId);
    final now = DateTime.now();
    final report = ServiceReport(
      id: reportId,
      workOrderId: workOrderId,
      complaint: complaint,
      cause: cause,
      correction: correction,
      collateral: collateral,
      comments: comments,
      techSignatureUrl: techSignatureUrl ?? existing?.techSignatureUrl,
      signedAt: techSignatureUrl == null ? existing?.signedAt : now,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      syncStatus: SyncStatusValues.pendingUpdate,
      lastSyncedAt: existing?.lastSyncedAt,
      lastError: null,
    );

    await _db.serviceReportsDao.upsert(
      _toCompanion(
        report,
        syncStatus: SyncStatusValues.pendingUpdate,
        updatedAt: now,
        lastSyncedAt: existing?.lastSyncedAt,
        lastError: null,
      ),
    );

    try {
      await supabase
          .from(AppConstants.tServiceReports)
          .upsert(_toRemoteRow(report), onConflict: 'id')
          .timeout(const Duration(seconds: 4));
      await _db.serviceReportsDao.upsert(
        _toCompanion(
          report.copyWith(syncStatus: SyncStatusValues.synced),
          syncStatus: SyncStatusValues.synced,
          updatedAt: now,
          lastSyncedAt: DateTime.now(),
          lastError: null,
        ),
      );
    } catch (error) {
      await markPending(reportId: reportId, error: error);
      throw const LocalServiceReportPendingException(
        'Saved locally. Sync pending.',
      );
    }
  }

  Future<void> markPending({
    required String reportId,
    required Object error,
  }) async {
    final existing = await _db.serviceReportsDao.getById(reportId);
    if (existing == null) return;
    await _db.serviceReportsDao.upsert(
      existing.toCompanion(true).copyWith(
            syncStatus: Value(existing.syncStatus == SyncStatusValues.synced
                ? SyncStatusValues.pendingUpdate
                : existing.syncStatus),
            updatedAt: Value(DateTime.now()),
            lastError: Value(error.toString()),
          ),
    );
  }

  Future<int> syncPendingServiceReports({
    String? reportId,
    String? workOrderId,
  }) async {
    final pendingRows = await _db.serviceReportsDao.listPendingSync();
    var syncedCount = 0;
    for (final row in pendingRows) {
      if (reportId != null && row.id != reportId) continue;
      if (workOrderId != null && row.workOrderId != workOrderId) continue;
      final report = _fromRow(row);
      try {
        await supabase
            .from(AppConstants.tServiceReports)
            .upsert(_toRemoteRow(report), onConflict: 'id')
            .timeout(const Duration(seconds: 4));
        await _db.serviceReportsDao.upsert(
          row.toCompanion(true).copyWith(
                syncStatus: const Value(SyncStatusValues.synced),
                lastSyncedAt: Value(DateTime.now()),
                lastError: const Value(null),
              ),
        );
        syncedCount++;
      } catch (error) {
        await markPending(reportId: row.id, error: error);
      }
    }
    return syncedCount;
  }

  Future<List<ServiceReport>> _cacheAndMergeRemote(
    List remoteRaw,
    List<ServiceReport> cached,
  ) async {
    final remote = remoteRaw
        .map((e) => ServiceReport.fromJson(e as Map<String, dynamic>))
        .toList();
    final localUnsyncedById = {
      for (final report in cached)
        if (report.syncStatus != SyncStatusValues.synced) report.id: report,
    };
    final now = DateTime.now();
    await _db.serviceReportsDao.upsertAll(
      remote
          .where((report) => !localUnsyncedById.containsKey(report.id))
          .map(
            (report) => _toCompanion(
              report,
              syncStatus: SyncStatusValues.synced,
              lastSyncedAt: now,
              lastError: null,
            ),
          )
          .toList(),
    );

    final byId = <String, ServiceReport>{
      for (final report in remote)
        report.id: report.copyWith(
          syncStatus: SyncStatusValues.synced,
          lastSyncedAt: now,
          lastError: null,
        ),
    };
    byId.addAll(localUnsyncedById);
    final merged = byId.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return merged;
  }
}

ServiceReport _fromRow(ServiceReportsTableData row) => ServiceReport(
      id: row.id,
      workOrderId: row.workOrderId,
      complaint: row.complaint,
      cause: row.cause,
      correction: row.correction,
      collateral: row.collateral,
      comments: row.comments,
      techSignatureUrl: row.techSignatureUrl,
      signedAt: row.signedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      syncStatus: row.syncStatus,
      lastSyncedAt: row.lastSyncedAt,
      lastError: row.lastError,
    );

ServiceReportsTableCompanion _toCompanion(
  ServiceReport report, {
  required String syncStatus,
  DateTime? updatedAt,
  DateTime? lastSyncedAt,
  String? lastError,
}) =>
    ServiceReportsTableCompanion(
      id: Value(report.id),
      workOrderId: Value(report.workOrderId),
      complaint: Value(report.complaint),
      cause: Value(report.cause),
      correction: Value(report.correction),
      collateral: Value(report.collateral),
      comments: Value(report.comments),
      techSignatureUrl: Value(report.techSignatureUrl),
      signedAt: Value(report.signedAt),
      createdAt: Value(report.createdAt),
      updatedAt: Value(updatedAt ?? report.updatedAt),
      syncStatus: Value(syncStatus),
      lastSyncedAt: Value(lastSyncedAt ?? report.lastSyncedAt),
      lastError: Value(lastError),
    );

Map<String, dynamic> _toRemoteRow(ServiceReport report) => {
      'id': report.id,
      'work_order_id': report.workOrderId,
      'complaint': report.complaint,
      'cause': report.cause,
      'correction': report.correction,
      'collateral': report.collateral,
      'comments': report.comments,
      'tech_signature_url': report.techSignatureUrl,
      'signed_at': report.signedAt?.toIso8601String(),
      'created_at': report.createdAt?.toIso8601String(),
      'updated_at': report.updatedAt?.toIso8601String(),
    };

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
