import 'dart:convert';

import 'maintenance_domain.dart';
import 'manual_fault_intake.dart';
import 'model.dart';

const correctivePlanningSetting = 'correctivePlanningV1';
const correctivePlanningRecordedEvent = 'corrective_planning_recorded_v1';
const correctivePlanningTitleLimit = 200;
const correctivePlanningDescriptionLimit = 10000;
const correctivePlanningRecordLimit = 10000;
const correctivePlanningStateByteLimit = 16 * 1024 * 1024;

enum CorrectivePlanningAction { create, edit, link }

class CorrectivePlanningFailure implements Exception {
  const CorrectivePlanningFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

Never _fail(String code, String message) =>
    throw CorrectivePlanningFailure(code, message);
Never _invalid() => _fail(
  'invalid_state',
  'Saved corrective planning is invalid. Its files have been retained.',
);

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _identity = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');
bool _id(dynamic value) => value is String && _identity.hasMatch(value);
bool _hash(dynamic value) => value is String && hashPattern.hasMatch(value);
bool _utc(dynamic value) =>
    value is String && DateTime.tryParse(value)?.isUtc == true;
bool _text(dynamic value, int limit, {bool empty = false}) =>
    value is String &&
    value.length <= limit &&
    value == value.trim() &&
    (empty || value.isNotEmpty);

Json _map(dynamic value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _shape(Json data, Set<String> keys) {
  if (data.length != keys.length || !data.keys.every(keys.contains)) _invalid();
}

void _version(Json data) {
  if (data['version'] is! int || data['version'] != 1) {
    _fail(
      'unsupported_version',
      'This corrective planning needs its matching app version. Its files have been retained.',
    );
  }
}

Json _hashed(Json data) => {...data, 'hash': contentHash(data)};
void _checkHash(Json data) {
  final clean = {...data}..remove('hash');
  if (!_hash(data['hash']) || data['hash'] != contentHash(clean)) _invalid();
}

abstract class _FrozenJson {
  _FrozenJson(Json value) : _encoded = canonical(value);
  final String _encoded;
  Json toJson() => jsonDecode(_encoded) as Json;
}

void _equipment(Json data) {
  _shape(data, {'id', 'name', 'serial', 'meterUnit'});
  if (!_id(data['id']) ||
      data['name'] is! String ||
      (data['name'] as String).trim().isEmpty ||
      (data['name'] as String).length > 200 ||
      data['serial'] is! String ||
      (data['serial'] as String).length > 200 ||
      !maintenanceMeterUnits.contains(data['meterUnit'])) {
    _invalid();
  }
}

class CorrectiveFaultReference extends _FrozenJson {
  CorrectiveFaultReference.fromJson(super.value) {
    final data = toJson();
    _shape(data, {'faultId', 'faultRecordHash'});
    if (data['faultId'] is! String ||
        !_uuid.hasMatch(data['faultId'] as String) ||
        !_hash(data['faultRecordHash'])) {
      _invalid();
    }
  }
  factory CorrectiveFaultReference.fromRecord(ManualFaultRecord record) =>
      CorrectiveFaultReference.fromJson({
        'faultId': record.id,
        'faultRecordHash': contentHash(record.toJson()),
      });
  String get faultId => toJson()['faultId'] as String;
  String get faultRecordHash => toJson()['faultRecordHash'] as String;
}

List<CorrectiveFaultReference> _references(dynamic raw) {
  if (raw is! List || raw.length > correctivePlanningRecordLimit) _invalid();
  final refs = [
    for (final value in raw) CorrectiveFaultReference.fromJson(_map(value)),
  ];
  String? previous;
  for (final ref in refs) {
    if (previous != null && previous.compareTo(ref.faultId) >= 0) _invalid();
    previous = ref.faultId;
  }
  return List.unmodifiable(refs);
}

List<Json> _sortedReferences(List<CorrectiveFaultReference> refs) {
  final sorted = refs.toList()..sort((a, b) => a.faultId.compareTo(b.faultId));
  final values = sorted.map((ref) => ref.toJson()).toList();
  _references(values);
  return values;
}

class FrozenCorrectivePlanningCommand extends _FrozenJson {
  FrozenCorrectivePlanningCommand.fromJson(super.value) {
    final data = toJson();
    _version(data);
    _shape(data, {
      'version',
      'id',
      'action',
      'companyId',
      'deviceId',
      'draftId',
      'equipmentId',
      'equipmentSnapshot',
      'expectedRevision',
      'expectedDraftHash',
      'title',
      'description',
      'faults',
      'createdAt',
      'hash',
    });
    if (data['id'] is! String ||
        !_uuid.hasMatch(data['id'] as String) ||
        !CorrectivePlanningAction.values.any((v) => v.name == data['action']) ||
        !_id(data['companyId']) ||
        !_id(data['deviceId']) ||
        !_id(data['draftId']) ||
        !_id(data['equipmentId']) ||
        !_utc(data['createdAt'])) {
      _invalid();
    }
    final refs = _references(data['faults']);
    if (data['action'] == 'create') {
      if (data['draftId'] != 'corrective-${data['id']}' ||
          data['expectedRevision'] != null ||
          data['expectedDraftHash'] != null) {
        _invalid();
      }
      final snapshot = _map(data['equipmentSnapshot']);
      _equipment(snapshot);
      if (snapshot['id'] != data['equipmentId']) _invalid();
    } else {
      if (data['equipmentSnapshot'] != null ||
          data['expectedRevision'] is! int ||
          data['expectedRevision'] < 1 ||
          data['expectedRevision'] > 1000000 ||
          !_hash(data['expectedDraftHash'])) {
        _invalid();
      }
    }
    if (data['action'] == 'link') {
      if (refs.isEmpty ||
          data['title'] != null ||
          data['description'] != null) {
        _invalid();
      }
    } else {
      if (!_text(data['title'], correctivePlanningTitleLimit) ||
          !_text(
            data['description'],
            correctivePlanningDescriptionLimit,
            empty: true,
          ) ||
          (data['action'] == 'edit' && refs.isNotEmpty)) {
        _invalid();
      }
    }
    _checkHash(data);
  }

  factory FrozenCorrectivePlanningCommand.createDraft({
    required String id,
    required String companyId,
    required String deviceId,
    required Json equipmentSnapshot,
    required String title,
    required String description,
    List<CorrectiveFaultReference> faults = const [],
    required String createdAt,
  }) => FrozenCorrectivePlanningCommand.fromJson(
    _hashed({
      'version': 1,
      'id': id.toLowerCase(),
      'action': 'create',
      'companyId': companyId,
      'deviceId': deviceId,
      'draftId': 'corrective-${id.toLowerCase()}',
      'equipmentId': equipmentSnapshot['id'],
      'equipmentSnapshot': equipmentSnapshot,
      'expectedRevision': null,
      'expectedDraftHash': null,
      'title': title.trim(),
      'description': description.trim(),
      'faults': _sortedReferences(faults),
      'createdAt': createdAt,
    }),
  );

  factory FrozenCorrectivePlanningCommand.editDraft({
    required String id,
    required String companyId,
    required String deviceId,
    required String draftId,
    required String equipmentId,
    required int expectedRevision,
    required String expectedDraftHash,
    required String title,
    required String description,
    required String createdAt,
  }) => FrozenCorrectivePlanningCommand.fromJson(
    _hashed({
      'version': 1,
      'id': id.toLowerCase(),
      'action': 'edit',
      'companyId': companyId,
      'deviceId': deviceId,
      'draftId': draftId,
      'equipmentId': equipmentId,
      'equipmentSnapshot': null,
      'expectedRevision': expectedRevision,
      'expectedDraftHash': expectedDraftHash,
      'title': title.trim(),
      'description': description.trim(),
      'faults': <Json>[],
      'createdAt': createdAt,
    }),
  );

  factory FrozenCorrectivePlanningCommand.linkFaults({
    required String id,
    required String companyId,
    required String deviceId,
    required String draftId,
    required String equipmentId,
    required int expectedRevision,
    required String expectedDraftHash,
    required List<CorrectiveFaultReference> faults,
    required String createdAt,
  }) => FrozenCorrectivePlanningCommand.fromJson(
    _hashed({
      'version': 1,
      'id': id.toLowerCase(),
      'action': 'link',
      'companyId': companyId,
      'deviceId': deviceId,
      'draftId': draftId,
      'equipmentId': equipmentId,
      'equipmentSnapshot': null,
      'expectedRevision': expectedRevision,
      'expectedDraftHash': expectedDraftHash,
      'title': null,
      'description': null,
      'faults': _sortedReferences(faults),
      'createdAt': createdAt,
    }),
  );

  String get id => toJson()['id'] as String;
  CorrectivePlanningAction get action =>
      CorrectivePlanningAction.values.byName(toJson()['action'] as String);
  String get companyId => toJson()['companyId'] as String;
  String get deviceId => toJson()['deviceId'] as String;
  String get draftId => toJson()['draftId'] as String;
  String get equipmentId => toJson()['equipmentId'] as String;
  Json? get equipmentSnapshot => toJson()['equipmentSnapshot'] as Json?;
  int? get expectedRevision => toJson()['expectedRevision'] as int?;
  String? get expectedDraftHash => toJson()['expectedDraftHash'] as String?;
  String? get title => toJson()['title'] as String?;
  String? get description => toJson()['description'] as String?;
  List<CorrectiveFaultReference> get faults => _references(toJson()['faults']);
  String get createdAt => toJson()['createdAt'] as String;
  String get hash => toJson()['hash'] as String;
}

class CorrectiveWorkDraft extends _FrozenJson {
  CorrectiveWorkDraft.fromJson(super.value) {
    final data = toJson();
    _version(data);
    _shape(data, {
      'version',
      'id',
      'companyId',
      'deviceId',
      'equipmentId',
      'equipmentSnapshot',
      'kind',
      'state',
      'revision',
      'title',
      'description',
      'faults',
      'createdAt',
      'updatedAt',
      'hash',
    });
    if (!_id(data['id']) ||
        !_id(data['companyId']) ||
        !_id(data['deviceId']) ||
        !_id(data['equipmentId']) ||
        data['kind'] != 'corrective' ||
        data['state'] != 'draft' ||
        data['revision'] is! int ||
        data['revision'] < 1 ||
        data['revision'] > 1000000 ||
        !_text(data['title'], correctivePlanningTitleLimit) ||
        !_text(
          data['description'],
          correctivePlanningDescriptionLimit,
          empty: true,
        ) ||
        !_utc(data['createdAt']) ||
        !_utc(data['updatedAt'])) {
      _invalid();
    }
    final snapshot = _map(data['equipmentSnapshot']);
    _equipment(snapshot);
    if (snapshot['id'] != data['equipmentId']) _invalid();
    _references(data['faults']);
    _checkHash(data);
  }
  String get id => toJson()['id'] as String;
  String get companyId => toJson()['companyId'] as String;
  String get deviceId => toJson()['deviceId'] as String;
  String get equipmentId => toJson()['equipmentId'] as String;
  Json get equipmentSnapshot => toJson()['equipmentSnapshot'] as Json;
  String get kind => 'corrective';
  String get state => 'draft';
  int get revision => toJson()['revision'] as int;
  String get title => toJson()['title'] as String;
  String get description => toJson()['description'] as String;
  List<CorrectiveFaultReference> get faults => _references(toJson()['faults']);
  String get createdAt => toJson()['createdAt'] as String;
  String get updatedAt => toJson()['updatedAt'] as String;
  String get hash => toJson()['hash'] as String;
}

CorrectiveWorkDraft _draftFor(
  FrozenCorrectivePlanningCommand command,
  CorrectiveWorkDraft? previous,
  String recordedAt,
) {
  if (command.action == CorrectivePlanningAction.create) {
    if (previous != null) _invalid();
  } else if (previous == null ||
      previous.id != command.draftId ||
      previous.companyId != command.companyId ||
      previous.deviceId != command.deviceId ||
      previous.equipmentId != command.equipmentId ||
      previous.revision != command.expectedRevision ||
      previous.hash != command.expectedDraftHash) {
    _invalid();
  }
  final refs = <CorrectiveFaultReference>[
    ...?previous?.faults,
    ...command.faults,
  ];
  return CorrectiveWorkDraft.fromJson(
    _hashed({
      'version': 1,
      'id': command.draftId,
      'companyId': command.companyId,
      'deviceId': command.deviceId,
      'equipmentId': command.equipmentId,
      'equipmentSnapshot':
          previous?.equipmentSnapshot ?? command.equipmentSnapshot,
      'kind': 'corrective',
      'state': 'draft',
      'revision': (previous?.revision ?? 0) + 1,
      'title': command.title ?? previous?.title,
      'description': command.description ?? previous?.description,
      'faults': _sortedReferences(refs),
      'createdAt': previous?.createdAt ?? command.createdAt,
      'updatedAt': recordedAt,
    }),
  );
}

class CorrectivePlanningReceipt extends _FrozenJson {
  CorrectivePlanningReceipt.fromJson(super.value) {
    final data = toJson();
    _version(data);
    _shape(data, {
      'version',
      'command',
      'previousDraft',
      'draft',
      'recordedAt',
      'hash',
    });
    if (!_utc(data['recordedAt'])) _invalid();
    final command = FrozenCorrectivePlanningCommand.fromJson(
      _map(data['command']),
    );
    final previous = data['previousDraft'] == null
        ? null
        : CorrectiveWorkDraft.fromJson(_map(data['previousDraft']));
    final draft = CorrectiveWorkDraft.fromJson(_map(data['draft']));
    if (canonical(draft.toJson()) !=
        canonical(
          _draftFor(command, previous, data['recordedAt'] as String).toJson(),
        )) {
      _invalid();
    }
    _checkHash(data);
  }
  factory CorrectivePlanningReceipt.create(
    FrozenCorrectivePlanningCommand command, {
    required CorrectiveWorkDraft? previousDraft,
    required String recordedAt,
  }) => CorrectivePlanningReceipt.fromJson(
    _hashed({
      'version': 1,
      'command': command.toJson(),
      'previousDraft': previousDraft?.toJson(),
      'draft': _draftFor(command, previousDraft, recordedAt).toJson(),
      'recordedAt': recordedAt,
    }),
  );
  FrozenCorrectivePlanningCommand get command =>
      FrozenCorrectivePlanningCommand.fromJson(_map(toJson()['command']));
  CorrectiveWorkDraft? get previousDraft => toJson()['previousDraft'] == null
      ? null
      : CorrectiveWorkDraft.fromJson(_map(toJson()['previousDraft']));
  CorrectiveWorkDraft get draft =>
      CorrectiveWorkDraft.fromJson(_map(toJson()['draft']));
  String get recordedAt => toJson()['recordedAt'] as String;
  String get commandId => command.id;
  String get hash => toJson()['hash'] as String;
}

class CorrectivePlanningState extends _FrozenJson {
  CorrectivePlanningState._(super.value);
  factory CorrectivePlanningState.empty() => CorrectivePlanningState._({
    'version': 1,
    'pending': <Json>[],
    'receipts': <Json>[],
  });
  List<FrozenCorrectivePlanningCommand> get pending => List.unmodifiable([
    for (final row in toJson()['pending'] as List)
      FrozenCorrectivePlanningCommand.fromJson(_map(row)),
  ]);
  List<CorrectivePlanningReceipt> get receipts => List.unmodifiable([
    for (final row in toJson()['receipts'] as List)
      CorrectivePlanningReceipt.fromJson(_map(row)),
  ]);
  List<CorrectiveWorkDraft> get drafts {
    final result = <String, CorrectiveWorkDraft>{};
    for (final receipt in receipts) {
      result[receipt.draft.id] = receipt.draft;
    }
    return List.unmodifiable(result.values);
  }

  CorrectiveWorkDraft? draftFor(String id) =>
      drafts.where((draft) => draft.id == id).firstOrNull;
  CorrectiveWorkDraft? draftForFault(String faultId) => drafts
      .where((draft) => draft.faults.any((ref) => ref.faultId == faultId))
      .firstOrNull;
}

void _authorityAndReferences(
  FrozenCorrectivePlanningCommand command,
  Json catalog,
  String deviceId,
  ManualFaultIntakeState history,
) {
  if (command.companyId != catalog['companyId'] ||
      command.deviceId != deviceId) {
    _fail(
      'authority_mismatch',
      'This planning request belongs to a different office or company.',
    );
  }
  if (!(catalog['equipment'] as List).any(
    (row) => row['id'] == command.equipmentId,
  )) {
    _fail('invalid_equipment', 'Choose existing company equipment.');
  }
  final records = {
    for (final receipt in history.receipts) receipt.record.id: receipt.record,
  };
  for (final ref in command.faults) {
    final fault = records[ref.faultId];
    if (fault == null ||
        fault.companyId != command.companyId ||
        fault.deviceId != deviceId ||
        fault.equipmentId != command.equipmentId ||
        ref.faultRecordHash != contentHash(fault.toJson())) {
      _fail(
        'invalid_fault',
        'Choose the original reported faults for this equipment.',
      );
    }
  }
}

/// Pure acceptance/preview. The store owns durable pending-intent checks and
/// atomic writes. An exact accepted UUID replay precedes current revision,
/// pending-request, link, or capacity checks and returns its original receipt.
CorrectivePlanningReceipt applyCorrectivePlanningCommand({
  required CorrectivePlanningState state,
  required FrozenCorrectivePlanningCommand command,
  required Json catalog,
  required String deviceId,
  required ManualFaultIntakeState manualFaultHistory,
  required String recordedAt,
}) {
  validateCatalog(catalog);
  final receipts = state.receipts;
  final prior = receipts
      .where((receipt) => receipt.commandId == command.id)
      .firstOrNull;
  if (prior != null) {
    if (canonical(prior.command.toJson()) != canonical(command.toJson())) {
      _fail(
        'command_conflict',
        'A different request cannot reuse this saved request identity.',
      );
    }
    _authorityAndReferences(
      prior.command,
      catalog,
      deviceId,
      manualFaultHistory,
    );
    return prior;
  }
  final pending = state.pending;
  if (pending.isNotEmpty &&
      canonical(pending.single.toJson()) != canonical(command.toJson())) {
    _fail(
      'pending_command',
      'Resume the saved planning request before entering another.',
    );
  }
  _authorityAndReferences(command, catalog, deviceId, manualFaultHistory);
  final drafts = state.drafts;
  final previous = drafts
      .where((draft) => draft.id == command.draftId)
      .firstOrNull;
  if (command.action == CorrectivePlanningAction.create) {
    if (previous != null ||
        (catalog['jobs'] as List).any((job) => job['id'] == command.draftId)) {
      _fail(
        'command_conflict',
        'This corrective draft identity is already in use.',
      );
    }
  } else {
    if (previous == null)
      _fail('draft_not_found', 'Choose an existing corrective work draft.');
    if (previous.equipmentId != command.equipmentId ||
        previous.companyId != command.companyId ||
        previous.deviceId != command.deviceId) {
      _fail(
        'authority_mismatch',
        'This request cannot change the draft equipment or office.',
      );
    }
    if (previous.revision != command.expectedRevision ||
        previous.hash != command.expectedDraftHash) {
      _fail(
        'stale_revision',
        'This draft changed. Open its latest saved version before planning.',
      );
    }
  }
  final linked = {
    for (final draft in drafts)
      for (final ref in draft.faults) ref.faultId,
  };
  if (command.faults.any((ref) => linked.contains(ref.faultId))) {
    _fail(
      'already_linked',
      'A selected fault already has corrective work planned. Open its linked draft.',
    );
  }
  final receipt = CorrectivePlanningReceipt.create(
    command,
    previousDraft: previous,
    recordedAt: recordedAt,
  );
  if (receipts.length >= correctivePlanningRecordLimit ||
      utf8
              .encode(
                canonical({
                  'version': 1,
                  'pending': <Json>[],
                  'receipts': [
                    ...receipts.map((r) => r.toJson()),
                    receipt.toJson(),
                  ],
                }),
              )
              .length >
          correctivePlanningStateByteLimit) {
    _fail(
      'capacity_reached',
      'This office planning history has reached its supported size. Saved drafts have been retained.',
    );
  }
  return receipt;
}

/// Validates receipt order/revision, not wall-clock order. Immutable equipment
/// context and original fault observations survive later catalog label changes.
CorrectivePlanningState validateCorrectivePlanning({
  required Json settings,
  required List<Json> events,
  required Json? catalog,
  required String deviceId,
  required ManualFaultIntakeState manualFaultHistory,
  required int databaseVersion,
}) {
  final ownEvents = events
      .where((row) => row['kind'] == correctivePlanningRecordedEvent)
      .toList();
  final present = settings.containsKey(correctivePlanningSetting);
  if ((databaseVersion == 0 || databaseVersion == 1) && catalog == null) {
    if (present || ownEvents.isNotEmpty) _invalid();
    return CorrectivePlanningState.empty();
  }
  if (databaseVersion == 2) {
    if (present || ownEvents.isNotEmpty) _invalid();
    return CorrectivePlanningState.empty();
  }
  if (databaseVersion != 3) {
    _fail(
      'unsupported_schema',
      'This workspace needs its matching app version. Its files have been retained.',
    );
  }
  if (!present || catalog == null || !_id(deviceId)) _invalid();
  validateCatalog(catalog);
  final data = _map(settings[correctivePlanningSetting]);
  _version(data);
  _shape(data, {'version', 'pending', 'receipts'});
  if (data['pending'] is! List ||
      (data['pending'] as List).length > 1 ||
      data['receipts'] is! List ||
      (data['receipts'] as List).length > correctivePlanningRecordLimit ||
      ((data['pending'] as List).isEmpty &&
          (data['receipts'] as List).isEmpty) ||
      utf8.encode(canonical(data)).length > correctivePlanningStateByteLimit) {
    _invalid();
  }
  final pending = [
    for (final row in data['pending'] as List)
      FrozenCorrectivePlanningCommand.fromJson(_map(row)),
  ];
  final accepted = [
    for (final row in data['receipts'] as List)
      CorrectivePlanningReceipt.fromJson(_map(row)),
  ];
  final replayed = <Json>[];
  final byId = <String, CorrectivePlanningReceipt>{};
  for (final receipt in accepted) {
    if (byId.containsKey(receipt.commandId)) _invalid();
    final expected = applyCorrectivePlanningCommand(
      state: CorrectivePlanningState._({
        'version': 1,
        'pending': <Json>[],
        'receipts': replayed,
      }),
      command: receipt.command,
      catalog: catalog,
      deviceId: deviceId,
      manualFaultHistory: manualFaultHistory,
      recordedAt: receipt.recordedAt,
    );
    if (canonical(expected.toJson()) != canonical(receipt.toJson())) _invalid();
    byId[receipt.commandId] = receipt;
    replayed.add(receipt.toJson());
  }
  final eventIds = <String>{};
  for (final event in ownEvents) {
    final receipt = CorrectivePlanningReceipt.fromJson(_map(event['payload']));
    if (!eventIds.add(receipt.commandId) ||
        byId[receipt.commandId] == null ||
        canonical(receipt.toJson()) !=
            canonical(byId[receipt.commandId]!.toJson())) {
      _invalid();
    }
  }
  if (eventIds.length != accepted.length) _invalid();
  if (pending.isNotEmpty) {
    final command = pending.single;
    if (byId.containsKey(command.id)) _invalid();
    applyCorrectivePlanningCommand(
      state: CorrectivePlanningState._({
        'version': 1,
        'pending': <Json>[],
        'receipts': replayed,
      }),
      command: command,
      catalog: catalog,
      deviceId: deviceId,
      manualFaultHistory: manualFaultHistory,
      recordedAt: command.createdAt,
    );
  }
  return CorrectivePlanningState._(data);
}
