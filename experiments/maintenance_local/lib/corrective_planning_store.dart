import 'dart:convert';

import 'corrective_planning.dart';
import 'lab_store.dart';
import 'manual_fault_intake.dart';
import 'model.dart';

/// Office-private planning over the existing queue, settings and transaction.
/// Frozen intent is persisted before acceptance; inspection storage is untouched.
class CorrectivePlanningStore {
  CorrectivePlanningStore(this._store);
  final LabStore _store;

  void _authority() {
    if (!_store.office) {
      throw const CorrectivePlanningFailure(
        'office_required',
        'Only the office computer can plan corrective work.',
      );
    }
    _store.requireOffice();
    if (_store.catalog == null) {
      throw const CorrectivePlanningFailure(
        'company_required',
        'Create a company and equipment before planning corrective work.',
      );
    }
  }

  _PlanningSnapshot _snapshot() {
    _authority();
    final settings = <String, dynamic>{
      for (final row in _store.db.select(
        'SELECT key,value FROM settings WHERE key IN (?,?)',
        [manualFaultIntakeSetting, correctivePlanningSetting],
      ))
        row['key'] as String: jsonDecode(row['value'] as String),
    };
    final events = <Json>[
      for (final row in _store.db.select(
        'SELECT kind,payload FROM events WHERE kind IN (?,?) ORDER BY id',
        [manualFaultReportedEvent, correctivePlanningRecordedEvent],
      ))
        {'kind': row['kind'], 'payload': jsonDecode(row['payload'] as String)},
    ];
    final catalog = _store.catalog!;
    final faults = validateManualFaultIntake(
      settings: settings,
      events: events,
      catalog: catalog,
      deviceId: _store.device,
      submissions: _store.submissions,
      receipts: _store.receipts,
    );
    final state = validateCorrectivePlanning(
      settings: settings,
      events: events,
      catalog: catalog,
      deviceId: _store.device,
      manualFaultHistory: faults,
      databaseVersion:
          _store.db.select('PRAGMA user_version').single.values.single as int,
    );
    return _PlanningSnapshot(catalog, faults, state);
  }

  Future<List<CorrectiveWorkDraft>> listDrafts() =>
      _store.queue.run(() async => _snapshot().state.drafts);

  Future<CorrectiveWorkDraft?> draftFor(String draftId) =>
      _store.queue.run(() async => _snapshot().state.draftFor(draftId));

  Future<CorrectiveWorkDraft?> draftForFault(String faultId) =>
      _store.queue.run(() async => _snapshot().state.draftForFault(faultId));

  Future<List<FrozenCorrectivePlanningCommand>> pendingCommands() =>
      _store.queue.run(() async => _snapshot().state.pending);

  Future<CorrectivePlanningReceipt?> receiptFor(String commandId) =>
      _store.queue.run(() async {
        final id = commandId.toLowerCase();
        return _snapshot().state.receipts
            .where((receipt) => receipt.commandId == id)
            .firstOrNull;
      });

  FrozenCorrectivePlanningCommand? _existing(
    CorrectivePlanningState state,
    String commandId,
  ) {
    final id = commandId.toLowerCase();
    return state.pending.where((command) => command.id == id).firstOrNull ??
        state.receipts
            .where((receipt) => receipt.commandId == id)
            .firstOrNull
            ?.command;
  }

  List<CorrectiveFaultReference> _references(
    ManualFaultIntakeState history,
    List<String> faultIds,
  ) {
    if (faultIds.toSet().length != faultIds.length) {
      throw const CorrectivePlanningFailure(
        'invalid_fault',
        'Choose each reported fault once.',
      );
    }
    final records = {
      for (final receipt in history.receipts) receipt.record.id: receipt.record,
    };
    return [
      for (final id in faultIds)
        if (records[id] case final record?)
          CorrectiveFaultReference.fromRecord(record)
        else
          throw const CorrectivePlanningFailure(
            'invalid_fault',
            'Choose an existing reported fault for this equipment.',
          ),
    ];
  }

  Future<FrozenCorrectivePlanningCommand> freezeCreate({
    required String equipmentId,
    required String title,
    required String description,
    List<String> faultIds = const [],
    required String commandId,
  }) {
    final capturedFaultIds = List<String>.unmodifiable(faultIds);
    return _freeze((snapshot) {
      final existing = _existing(snapshot.state, commandId);
      if (existing != null &&
          (existing.action != CorrectivePlanningAction.create ||
              existing.equipmentId != equipmentId)) {
        _conflict();
      }
      final equipment = (snapshot.catalog['equipment'] as List)
          .cast<Json>()
          .where((row) => row['id'] == equipmentId)
          .firstOrNull;
      if (equipment == null) {
        throw const CorrectivePlanningFailure(
          'invalid_equipment',
          'Choose existing company equipment.',
        );
      }
      return FrozenCorrectivePlanningCommand.createDraft(
        id: commandId,
        companyId: snapshot.catalog['companyId'] as String,
        deviceId: _store.device,
        equipmentSnapshot: existing?.equipmentSnapshot ?? equipment,
        title: title,
        description: description,
        faults: _references(snapshot.faults, capturedFaultIds),
        createdAt: existing?.createdAt ?? _store.stamp(),
      );
    });
  }

  Future<FrozenCorrectivePlanningCommand> freezeEdit({
    required String draftId,
    required int expectedRevision,
    required String expectedDraftHash,
    required String title,
    required String description,
    required String commandId,
  }) => _freeze((snapshot) {
    final existing = _existing(snapshot.state, commandId);
    if (existing != null && existing.action != CorrectivePlanningAction.edit) {
      _conflict();
    }
    final draft = _draft(snapshot.state, draftId);
    return FrozenCorrectivePlanningCommand.editDraft(
      id: commandId,
      companyId: snapshot.catalog['companyId'] as String,
      deviceId: _store.device,
      draftId: draftId,
      equipmentId: draft.equipmentId,
      expectedRevision: expectedRevision,
      expectedDraftHash: expectedDraftHash,
      title: title,
      description: description,
      createdAt: existing?.createdAt ?? _store.stamp(),
    );
  });

  Future<FrozenCorrectivePlanningCommand> freezeLink({
    required String draftId,
    required int expectedRevision,
    required String expectedDraftHash,
    required List<String> faultIds,
    required String commandId,
  }) {
    final capturedFaultIds = List<String>.unmodifiable(faultIds);
    return _freeze((snapshot) {
      final existing = _existing(snapshot.state, commandId);
      if (existing != null &&
          existing.action != CorrectivePlanningAction.link) {
        _conflict();
      }
      final draft = _draft(snapshot.state, draftId);
      return FrozenCorrectivePlanningCommand.linkFaults(
        id: commandId,
        companyId: snapshot.catalog['companyId'] as String,
        deviceId: _store.device,
        draftId: draftId,
        equipmentId: draft.equipmentId,
        expectedRevision: expectedRevision,
        expectedDraftHash: expectedDraftHash,
        faults: _references(snapshot.faults, capturedFaultIds),
        createdAt: existing?.createdAt ?? _store.stamp(),
      );
    });
  }

  CorrectiveWorkDraft _draft(CorrectivePlanningState state, String id) {
    final draft = state.draftFor(id);
    if (draft == null) {
      throw const CorrectivePlanningFailure(
        'invalid_draft',
        'Choose a saved corrective work draft. Inspection work cannot receive these links.',
      );
    }
    return draft;
  }

  Future<FrozenCorrectivePlanningCommand> _freeze(
    FrozenCorrectivePlanningCommand Function(_PlanningSnapshot) create,
  ) => _store.queue.run(() async {
    _authority();
    late FrozenCorrectivePlanningCommand frozen;
    _store.transaction(() {
      final snapshot = _snapshot();
      final command = create(snapshot);
      final existing = _existing(snapshot.state, command.id);
      if (existing != null) {
        if (existing.hash != command.hash) _conflict();
        frozen = existing;
        return;
      }
      if (snapshot.state.pending.isNotEmpty) {
        throw const CorrectivePlanningFailure(
          'pending_command',
          'Resume the saved planning request before entering another change.',
        );
      }
      final preview = applyCorrectivePlanningCommand(
        state: snapshot.state,
        command: command,
        catalog: snapshot.catalog,
        deviceId: _store.device,
        manualFaultHistory: snapshot.faults,
        recordedAt: command.createdAt,
      );
      final accepted = _ledger(snapshot.state, receipt: preview);
      if (snapshot.state.receipts.length >= correctivePlanningRecordLimit ||
          utf8.encode(canonical(accepted)).length + 64 >
              correctivePlanningStateByteLimit) {
        throw const CorrectivePlanningFailure(
          'capacity_reached',
          'This office planning history has reached its supported size. Saved drafts have been retained.',
        );
      }
      _store.setSetting(
        correctivePlanningSetting,
        _ledger(snapshot.state, pending: command),
      );
      _store.db.execute('PRAGMA user_version=3');
      _snapshot();
      frozen = command;
    });
    return frozen;
  });

  Future<CorrectivePlanningReceipt> apply(
    FrozenCorrectivePlanningCommand command,
  ) => _store.queue.run(() async {
    _authority();
    late CorrectivePlanningReceipt accepted;
    _store.transaction(() {
      final snapshot = _snapshot();
      final prior = snapshot.state.receipts
          .where((receipt) => receipt.commandId == command.id)
          .firstOrNull;
      if (prior != null) {
        if (prior.command.hash != command.hash) _conflict();
        accepted = prior;
        return;
      }
      final pending = snapshot.state.pending
          .where((row) => row.id == command.id)
          .firstOrNull;
      if (pending == null || pending.hash != command.hash) {
        throw const CorrectivePlanningFailure(
          'command_conflict',
          'Resume the exact saved planning request. Different fields cannot replace it.',
        );
      }
      accepted = applyCorrectivePlanningCommand(
        state: snapshot.state,
        command: command,
        catalog: snapshot.catalog,
        deviceId: _store.device,
        manualFaultHistory: snapshot.faults,
        recordedAt: _store.stamp(),
      );
      _store.setSetting(
        correctivePlanningSetting,
        _ledger(snapshot.state, receipt: accepted),
      );
      _store.event(correctivePlanningRecordedEvent, accepted.toJson());
      _snapshot();
    });
    return accepted;
  });

  Json _ledger(
    CorrectivePlanningState state, {
    FrozenCorrectivePlanningCommand? pending,
    CorrectivePlanningReceipt? receipt,
  }) => {
    'version': 1,
    'pending': [if (pending != null) pending.toJson()],
    'receipts': [
      ...state.receipts.map((row) => row.toJson()),
      if (receipt != null) receipt.toJson(),
    ],
  };

  Never _conflict() => throw const CorrectivePlanningFailure(
    'command_conflict',
    'This planning request identity belongs to different frozen fields. Resume the original request.',
  );
}

class _PlanningSnapshot {
  _PlanningSnapshot(this.catalog, this.faults, this.state);
  final Json catalog;
  final ManualFaultIntakeState faults;
  final CorrectivePlanningState state;
}
