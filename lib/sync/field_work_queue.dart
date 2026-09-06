import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, AuthException;
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/db/database.dart';

class FieldOperation {
  const FieldOperation({
    required this.id,
    required this.kind,
    required this.subject,
    required this.payload,
    this.status = 'pending',
    this.error,
    this.attempts = 0,
  });
  final String id, kind, subject, status;
  final Map<String, dynamic> payload;
  final String? error;
  final int attempts;
  bool get needsAttention => status == 'failed';
  bool get synced => status == 'synced';
}

typedef SendFieldOperation = Future<void> Function(FieldOperation operation);

/// Durable account-owned outbox. An acknowledgement is the only transition to
/// synced. A lost response retries the same immutable operation ID and payload.
class FieldWorkQueue {
  FieldWorkQueue(
    this.db, {
    required this.account,
    required this.currentAccount,
    required this.send,
  });
  final AppDatabase db;
  final String account;
  final String? Function() currentAccount;
  final SendFieldOperation send;
  Future<void>? _flushing;
  bool _closed = false;
  void close() => _closed = true;
  void checkAccount() {
    if (_closed || !db.belongsTo(account) || currentAccount() != account) {
      throw const AccountChangedException();
    }
  }

  FieldOperation _operation(SyncOperationsTableData row) {
    final stored = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    if (stored['account'] != account) throw const AccountChangedException();
    return FieldOperation(
      id: row.id,
      kind: row.operationType,
      subject: row.entityRemoteId ?? '',
      payload: Map<String, dynamic>.from(stored['data'] as Map),
      status: row.status,
      error: row.lastError,
      attempts: row.attemptCount,
    );
  }

  int _sequence(SyncOperationsTableData row) =>
      (jsonDecode(row.payloadJson) as Map)['sequence'] as int? ??
      row.createdAt?.microsecondsSinceEpoch ??
      0;
  Future<List<FieldOperation>> list() async {
    checkAccount();
    final rows = await (db.select(
      db.syncOperationsTable,
    )..where((t) => t.entityType.equals('field_work'))).get();
    checkAccount();
    rows.sort((a, b) => _sequence(a).compareTo(_sequence(b)));
    return rows.map(_operation).toList();
  }

  Stream<List<FieldOperation>> watch() =>
      (db.select(
        db.syncOperationsTable,
      )..where((t) => t.entityType.equals('field_work'))).watch().map((rows) {
        checkAccount();
        rows.sort((a, b) => _sequence(a).compareTo(_sequence(b)));
        return rows.map(_operation).toList();
      });
  Future<FieldOperation> enqueue(FieldOperation operation) async {
    checkAccount();
    await db.transaction(() async {
      final previous = await (db.select(
        db.syncOperationsTable,
      )..where((t) => t.id.equals(operation.id))).getSingleOrNull();
      if (previous != null) {
        final stored = jsonDecode(previous.payloadJson) as Map;
        if (stored['account'] != account ||
            jsonEncode(stored['data']) != jsonEncode(operation.payload) ||
            previous.operationType != operation.kind ||
            previous.entityRemoteId != operation.subject) {
          throw StateError(
            'An upload identifier cannot be reused for different input.',
          );
        }
        return;
      }
      final previousRows = await (db.select(
        db.syncOperationsTable,
      )..where((t) => t.entityType.equals('field_work'))).get();
      var sequence = DateTime.now().microsecondsSinceEpoch;
      for (final row in previousRows) {
        if (_sequence(row) >= sequence) sequence = _sequence(row) + 1;
      }
      final payload = jsonEncode({
        'account': account,
        'data': operation.payload,
        'sequence': sequence,
      });
      await db
          .into(db.syncOperationsTable)
          .insert(
            SyncOperationsTableCompanion(
              id: Value(operation.id),
              entityType: const Value('field_work'),
              entityRemoteId: Value(operation.subject),
              operationType: Value(operation.kind),
              payloadJson: Value(payload),
              status: const Value('pending'),
              createdAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    });
    return (await list()).singleWhere((row) => row.id == operation.id);
  }

  Future<void> submit(FieldOperation operation) async {
    await enqueue(operation);
    await flush();
  }

  Future<void> flush({bool retryFailed = false}) {
    if (_flushing != null) return _flushing!;
    final future = _flush(retryFailed: retryFailed);
    _flushing = future;
    return future.whenComplete(() => _flushing = null);
  }

  Future<void> _flush({required bool retryFailed}) async {
    checkAccount();
    final blocked = <String>{};
    for (final operation in await list()) {
      checkAccount();
      if (operation.synced || operation.status == 'cancelled') continue;
      if (blocked.contains(operation.subject)) continue;
      if (operation.needsAttention && !retryFailed) {
        blocked.add(operation.subject);
        continue;
      }
      try {
        await send(operation);
        checkAccount();
        await _update(operation, 'synced', null);
      } on AccountChangedException {
        rethrow;
      } catch (error) {
        checkAccount();
        final rejected =
            error is PostgrestException ||
            error is AuthException ||
            error is FormatException ||
            error is StateError;
        await _update(
          operation,
          rejected ? 'failed' : 'pending',
          error.toString(),
        );
        if (rejected) {
          blocked.add(operation.subject);
        } else {
          break;
        }
      }
    }
  }

  Future<void> archiveSubject(String subject) async {
    checkAccount();
    if (_flushing != null) await _flushing;
    checkAccount();
    for (final operation in await list()) {
      if (operation.subject == subject && !operation.synced) {
        await _update(operation, 'cancelled', operation.error);
      }
    }
  }

  /// A corrected report may reuse evidence from its archived submission.
  /// Restore only those explicitly selected immutable uploads, never old writes.
  Future<void> restoreEvidence(Iterable<String> paths) async {
    checkAccount();
    final selected = paths.toSet();
    for (final operation in await list()) {
      if (operation.kind == 'upload' &&
          operation.status == 'cancelled' &&
          selected.contains(operation.payload['path'])) {
        await _update(operation, 'pending', null);
      }
    }
  }

  Future<void> _update(
    FieldOperation operation,
    String status,
    String? error,
  ) =>
      (db.update(
        db.syncOperationsTable,
      )..where((t) => t.id.equals(operation.id))).write(
        SyncOperationsTableCompanion(
          status: Value(status),
          lastError: Value(error),
          attemptCount: Value(operation.attempts + 1),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
}
