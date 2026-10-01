import 'dart:convert';

import 'lab_store.dart';
import 'manual_fault_intake.dart';
import 'model.dart';

/// Office-only manual intake composed over the existing seven-table store.
/// A durable pending command is the only writable intent. Acceptance binds its
/// exact contents to one immutable record, receipt, and event in a transaction.
class ManualFaultIntakeStore {
  ManualFaultIntakeStore(this._store);
  final LabStore _store;

  void _authority() {
    if (!_store.office) {
      throw const ManualFaultIntakeFailure(
        'office_required',
        'Only the office computer can report a manual fault.',
      );
    }
    _store.requireOffice();
    if (_store.catalog == null) {
      throw const ManualFaultIntakeFailure(
        'company_required',
        'Create a company and equipment before reporting a fault.',
      );
    }
  }

  List<Json> _events() => [
    for (final row in _store.db.select(
      'SELECT kind,payload FROM events WHERE kind=? ORDER BY id',
      [manualFaultReportedEvent],
    ))
      {'kind': row['kind'], 'payload': jsonDecode(row['payload'] as String)},
  ];

  ManualFaultIntakeState _state() {
    _authority();
    final rows = _store.db.select('SELECT value FROM settings WHERE key=?', [
      manualFaultIntakeSetting,
    ]);
    return validateManualFaultIntake(
      settings: {
        if (rows.isNotEmpty)
          manualFaultIntakeSetting: jsonDecode(rows.single['value'] as String),
      },
      events: _events(),
      catalog: _store.catalog,
      deviceId: _store.device,
      submissions: _store.submissions,
      receipts: _store.receipts,
    );
  }

  Future<List<ManualFaultRecord>> listRecords() => _store.queue.run(() async {
    return List.unmodifiable(
      _state().receipts.map((receipt) => receipt.record),
    );
  });

  Future<List<ManualFaultOrigin>> availableOrigins(String equipmentId) =>
      _store.queue.run(() async {
        _state();
        return manualFaultAvailableOrigins(
          catalog: _store.catalog!,
          equipmentId: equipmentId,
          submissions: _store.submissions,
          receipts: _store.receipts,
        );
      });

  Future<List<FrozenManualFaultCommand>> pendingCommands() =>
      _store.queue.run(() async => _state().pending);

  Future<ManualFaultReceipt?> receiptFor(String commandId) => _store.queue.run(
    () async {
      final id = commandId.toLowerCase();
      return _state().receipts.where((row) => row.commandId == id).firstOrNull;
    },
  );

  Future<FrozenManualFaultCommand> freeze({
    required String equipmentId,
    required String description,
    required ManualFaultSeverity severity,
    ManualFaultOrigin? originSelection,
    required String commandId,
  }) => _store.queue.run(() async {
    final state = _state();
    final id = commandId.toLowerCase();
    final existing =
        state.pending.where((command) => command.id == id).firstOrNull ??
        state.receipts
            .where((receipt) => receipt.commandId == id)
            .firstOrNull
            ?.command;
    final command = FrozenManualFaultCommand.create(
      id: commandId,
      companyId: _store.catalog!['companyId'] as String,
      deviceId: _store.device,
      equipmentId: equipmentId,
      description: description,
      severity: severity,
      origin: originSelection,
      createdAt: existing?.createdAt ?? _store.stamp(),
    );
    if (existing != null) {
      if (command.hash != existing.hash) _conflict();
      return existing;
    }
    if (state.pending.isNotEmpty) {
      throw const ManualFaultIntakeFailure(
        'pending_command',
        'Resume the saved fault request before entering another report.',
      );
    }
    if (!(_store.catalog!['equipment'] as List).any(
      (row) => row['id'] == equipmentId,
    )) {
      throw const ManualFaultIntakeFailure(
        'invalid_origin',
        'Choose existing company equipment.',
      );
    }
    if (originSelection != null) {
      final choices = manualFaultAvailableOrigins(
        catalog: _store.catalog!,
        equipmentId: equipmentId,
        submissions: _store.submissions,
        receipts: _store.receipts,
      );
      if (!choices.any(
        (choice) =>
            canonical(choice.toJson()) == canonical(originSelection.toJson()),
      )) {
        throw const ManualFaultIntakeFailure(
          'invalid_origin',
          'This saved inspection selection changed. Refresh its captured observation before reporting.',
        );
      }
    }
    _store.transaction(() {
      _authority();
      _store.setSetting(manualFaultIntakeSetting, {
        'version': 1,
        'pending': [command.toJson()],
        'receipts': state.receipts.map((receipt) => receipt.toJson()).toList(),
      });
      _state();
    });
    return command;
  });

  Future<ManualFaultReceipt> record(
    FrozenManualFaultCommand command,
  ) => _store.queue.run(() async {
    final state = _state();
    final prior = state.receipts
        .where((row) => row.commandId == command.id)
        .firstOrNull;
    if (prior != null) {
      if (prior.command.hash != command.hash) _conflict();
      return prior;
    }
    final pending = state.pending
        .where((row) => row.id == command.id)
        .firstOrNull;
    if (pending == null || pending.hash != command.hash) {
      throw const ManualFaultIntakeFailure(
        'command_conflict',
        'Resume the exact saved fault request. A different request cannot replace it.',
      );
    }
    final receipt = ManualFaultReceipt.create(
      command,
      reportedAt: _store.stamp(),
    );
    _store.transaction(() {
      _authority();
      _store.setSetting(manualFaultIntakeSetting, {
        'version': 1,
        'pending': <Json>[],
        'receipts': [
          ...state.receipts.map((row) => row.toJson()),
          receipt.toJson(),
        ],
      });
      _store.event(manualFaultReportedEvent, receipt.toJson());
      _state();
    });
    return receipt;
  });

  Never _conflict() => throw const ManualFaultIntakeFailure(
    'command_conflict',
    'This fault request identity already belongs to different frozen fields. Resume the original request.',
  );
}
