import 'dart:convert';

import 'maintenance_domain.dart';
import 'model.dart';

const manualFaultIntakeSetting = 'manualFaultIntakeV1';
const manualFaultReportedEvent = 'manual_fault_reported_v1';
const manualFaultReportedStatus = 'Reported — corrective work not planned';
const manualFaultDescriptionLimit = 10000;
const manualFaultRecordLimit = 10000;
const manualFaultStateByteLimit = 16 * 1024 * 1024;

enum ManualFaultSeverity { normal, urgent }

enum ManualFaultOriginKind { submission, item, note }

enum ManualFaultObservation { pending, approved, returned }

class ManualFaultIntakeFailure implements Exception {
  const ManualFaultIntakeFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

Never _invalid([String? detail]) => throw ManualFaultIntakeFailure(
  'invalid_state',
  detail ?? 'Saved fault history is invalid. Its files have been retained.',
);

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _identity = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');
bool _id(dynamic value) => value is String && _identity.hasMatch(value);
bool _hash(dynamic value) => value is String && hashPattern.hasMatch(value);
bool _date(dynamic value) =>
    value is String && DateTime.tryParse(value)?.isUtc == true;
Json _map(dynamic value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _shape(Json value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    _invalid();
  }
}

void _version(Json value) {
  if (value['version'] != 1 || value['version'] is! int) {
    throw const ManualFaultIntakeFailure(
      'unsupported_version',
      'This fault history needs its matching app version. Its files have been retained.',
    );
  }
}

Json _hashed(Json value) => {...value, 'hash': contentHash(value)};
void _checkHash(Json value) {
  final clean = {...value}..remove('hash');
  if (!_hash(value['hash']) || value['hash'] != contentHash(clean)) _invalid();
}

/// Every getter returns decoded copies. Callers cannot alter a saved command,
/// captured observation, record, or receipt by mutating nested JSON.
abstract class _FrozenJson {
  _FrozenJson(Json value) : _encoded = canonical(value);
  final String _encoded;
  Json toJson() => jsonDecode(_encoded) as Json;
}

class ManualFaultOrigin extends _FrozenJson {
  ManualFaultOrigin.fromJson(super.value) {
    _validateOriginShape(toJson());
  }
  ManualFaultOriginKind get kind =>
      ManualFaultOriginKind.values.byName(toJson()['kind'] as String);
  String get submissionId => toJson()['submissionId'] as String;
  String get submissionHash => toJson()['submissionHash'] as String;
  String get documentHash => toJson()['documentHash'] as String;
  String get jobId => toJson()['jobId'] as String;
  int get submissionRevision => toJson()['submissionRevision'] as int;
  String get snapshotHash => toJson()['snapshotHash'] as String;
  String? get itemId => toJson()['itemId'] as String?;
  ManualFaultObservation get observation =>
      ManualFaultObservation.values.byName(toJson()['observation'] as String);
  String? get receiptId => toJson()['receiptId'] as String?;
  String? get receiptHash => toJson()['receiptHash'] as String?;
  String get label => toJson()['label'] as String;
}

void _validateOriginShape(Json value) {
  _shape(value, {
    'version',
    'kind',
    'submissionId',
    'submissionHash',
    'documentHash',
    'jobId',
    'submissionRevision',
    'snapshotHash',
    'itemId',
    'observation',
    'receiptId',
    'receiptHash',
    'label',
  });
  _version(value);
  if (!ManualFaultOriginKind.values.any((v) => v.name == value['kind']) ||
      !ManualFaultObservation.values.any(
        (v) => v.name == value['observation'],
      ) ||
      !_id(value['submissionId']) ||
      !_id(value['jobId']) ||
      !_hash(value['submissionHash']) ||
      !_hash(value['documentHash']) ||
      !_hash(value['snapshotHash']) ||
      value['submissionRevision'] is! int ||
      value['submissionRevision'] < 1 ||
      value['submissionRevision'] > 1000000 ||
      value['label'] is! String ||
      (value['label'] as String).isEmpty ||
      (value['label'] as String).length > 1400 ||
      (value['kind'] == 'item'
          ? !_id(value['itemId'])
          : value['itemId'] != null) ||
      (value['observation'] == 'pending'
          ? value['receiptId'] != null || value['receiptHash'] != null
          : !_id(value['receiptId']) || !_hash(value['receiptHash']))) {
    _invalid();
  }
}

class FrozenManualFaultCommand extends _FrozenJson {
  FrozenManualFaultCommand.fromJson(super.value) {
    final data = toJson();
    _shape(data, {
      'version',
      'id',
      'companyId',
      'deviceId',
      'equipmentId',
      'description',
      'severity',
      'origin',
      'createdAt',
      'hash',
    });
    _version(data);
    _checkHash(data);
    if (data['id'] is! String ||
        !_uuid.hasMatch(data['id'] as String) ||
        !_id(data['companyId']) ||
        !_id(data['deviceId']) ||
        !_id(data['equipmentId']) ||
        data['description'] is! String ||
        (data['description'] as String).trim().isEmpty ||
        data['description'] != (data['description'] as String).trim() ||
        (data['description'] as String).length > manualFaultDescriptionLimit ||
        !ManualFaultSeverity.values.any((v) => v.name == data['severity']) ||
        !_date(data['createdAt'])) {
      _invalid();
    }
    if (data['origin'] != null) {
      ManualFaultOrigin.fromJson(_map(data['origin']));
    }
  }
  factory FrozenManualFaultCommand.create({
    required String id,
    required String companyId,
    required String deviceId,
    required String equipmentId,
    required String description,
    required ManualFaultSeverity severity,
    ManualFaultOrigin? origin,
    required String createdAt,
  }) => FrozenManualFaultCommand.fromJson(
    _hashed({
      'version': 1,
      'id': id.toLowerCase(),
      'companyId': companyId,
      'deviceId': deviceId,
      'equipmentId': equipmentId,
      'description': description.trim(),
      'severity': severity.name,
      'origin': origin?.toJson(),
      'createdAt': createdAt,
    }),
  );
  String get id => toJson()['id'] as String;
  String get companyId => toJson()['companyId'] as String;
  String get deviceId => toJson()['deviceId'] as String;
  String get equipmentId => toJson()['equipmentId'] as String;
  String get description => toJson()['description'] as String;
  ManualFaultSeverity get severity =>
      ManualFaultSeverity.values.byName(toJson()['severity'] as String);
  ManualFaultOrigin? get origin => toJson()['origin'] == null
      ? null
      : ManualFaultOrigin.fromJson(_map(toJson()['origin']));
  String get createdAt => toJson()['createdAt'] as String;
  String get hash => toJson()['hash'] as String;
}

class ManualFaultRecord extends _FrozenJson {
  ManualFaultRecord.fromJson(super.value) {
    final data = toJson();
    _shape(data, {
      'version',
      'id',
      'commandId',
      'companyId',
      'deviceId',
      'equipmentId',
      'description',
      'severity',
      'origin',
      'reportedAt',
      'status',
      'requestHash',
      'hash',
    });
    _version(data);
    _checkHash(data);
    if (data['id'] is! String ||
        !_uuid.hasMatch(data['id'] as String) ||
        data['id'] != data['commandId'] ||
        !_id(data['companyId']) ||
        !_id(data['deviceId']) ||
        !_id(data['equipmentId']) ||
        data['description'] is! String ||
        (data['description'] as String).trim().isEmpty ||
        data['description'] != (data['description'] as String).trim() ||
        (data['description'] as String).length > manualFaultDescriptionLimit ||
        !ManualFaultSeverity.values.any((v) => v.name == data['severity']) ||
        !_hash(data['requestHash']) ||
        data['status'] != manualFaultReportedStatus ||
        !_date(data['reportedAt'])) {
      _invalid();
    }
    if (data['origin'] != null) {
      ManualFaultOrigin.fromJson(_map(data['origin']));
    }
    // The receipt validator also binds these fields to the frozen command.
  }
  String get id => toJson()['id'] as String;
  String get commandId => toJson()['commandId'] as String;
  String get companyId => toJson()['companyId'] as String;
  String get deviceId => toJson()['deviceId'] as String;
  String get equipmentId => toJson()['equipmentId'] as String;
  String get description => toJson()['description'] as String;
  ManualFaultSeverity get severity =>
      ManualFaultSeverity.values.byName(toJson()['severity'] as String);
  ManualFaultOrigin? get origin => toJson()['origin'] == null
      ? null
      : ManualFaultOrigin.fromJson(_map(toJson()['origin']));
  String get reportedAt => toJson()['reportedAt'] as String;
  String get status => manualFaultReportedStatus;
}

class ManualFaultReceipt extends _FrozenJson {
  ManualFaultReceipt.fromJson(super.value) {
    final data = toJson();
    _shape(data, {'version', 'command', 'record', 'hash'});
    _version(data);
    _checkHash(data);
    final command = FrozenManualFaultCommand.fromJson(_map(data['command']));
    final record = ManualFaultRecord.fromJson(_map(data['record']));
    final expected = _recordFor(command, record.reportedAt);
    if (canonical(record.toJson()) != canonical(expected)) {
      _invalid();
    }
  }
  factory ManualFaultReceipt.create(
    FrozenManualFaultCommand command, {
    required String reportedAt,
  }) => ManualFaultReceipt.fromJson(
    _hashed({
      'version': 1,
      'command': command.toJson(),
      'record': _recordFor(command, reportedAt),
    }),
  );
  FrozenManualFaultCommand get command =>
      FrozenManualFaultCommand.fromJson(_map(toJson()['command']));
  ManualFaultRecord get record =>
      ManualFaultRecord.fromJson(_map(toJson()['record']));
  String get commandId => command.id;
  String get hash => toJson()['hash'] as String;
}

Json _recordFor(FrozenManualFaultCommand command, String reportedAt) =>
    _hashed({
      'version': 1,
      'id': command.id,
      'commandId': command.id,
      'companyId': command.companyId,
      'deviceId': command.deviceId,
      'equipmentId': command.equipmentId,
      'description': command.description,
      'severity': command.severity.name,
      'origin': command.origin?.toJson(),
      'reportedAt': reportedAt,
      'status': manualFaultReportedStatus,
      'requestHash': command.hash,
    });

class ManualFaultIntakeState extends _FrozenJson {
  ManualFaultIntakeState._(super.value);
  factory ManualFaultIntakeState.empty() => ManualFaultIntakeState._({
    'version': 1,
    'pending': <Json>[],
    'receipts': <Json>[],
  });
  List<FrozenManualFaultCommand> get pending => List.unmodifiable([
    for (final value in toJson()['pending'] as List)
      FrozenManualFaultCommand.fromJson(_map(value)),
  ]);
  List<ManualFaultReceipt> get receipts => List.unmodifiable([
    for (final value in toJson()['receipts'] as List)
      ManualFaultReceipt.fromJson(_map(value)),
  ]);
}

/// Reads only saved submissions. No draft document is accepted as an origin.
/// Backup callers validate document decoding/evidence with their existing
/// boundary first; this pure validator checks saved bytes, values and references
/// without invoking native documents or changing storage.
List<ManualFaultOrigin> manualFaultAvailableOrigins({
  required Json catalog,
  required String equipmentId,
  required List<Json> submissions,
  required List<Json> receipts,
}) {
  validateCatalog(catalog);
  if (!(catalog['equipment'] as List).any((row) => row['id'] == equipmentId)) {
    throw const ManualFaultIntakeFailure(
      'invalid_origin',
      'Choose existing company equipment.',
    );
  }
  final sources = _sourceIndex(catalog, submissions, receipts);
  final result = <ManualFaultOrigin>[];
  for (final source in sources.submissions.values) {
    if (source['equipmentId'] != equipmentId) continue;
    final receipt = sources.receipts[source['id']];
    final observation = receipt == null ? 'pending' : receipt['decision'];
    result.add(
      _originFor(source, receipt, 'submission', null, observation as String),
    );
    for (final item
        in (source['context']['checklistSnapshot']['items'] as List)) {
      result.add(
        _originFor(source, receipt, 'item', item['id'] as String, observation),
      );
    }
    if ((source['values']['notes'] as String).trim().isNotEmpty) {
      result.add(_originFor(source, receipt, 'note', null, observation));
    }
  }
  return List.unmodifiable(result);
}

class _Sources {
  _Sources(this.submissions, this.receipts);
  final Map<String, Json> submissions, receipts;
}

_Sources _sourceIndex(
  Json catalog,
  List<Json> submissions,
  List<Json> receipts,
) {
  if (submissions.length > 100000 || receipts.length > 100000) _invalid();
  final sources = <String, Json>{}, decisions = <String, Json>{};
  final receiptIds = <String>{};
  for (final raw in submissions) {
    final source = {...raw}..remove('_state');
    _shape(source, {
      'id',
      'companyId',
      'jobId',
      'device',
      'createdAt',
      'document',
      'documentHash',
      'values',
      'schemaVersion',
      'equipmentId',
      'snapshotHash',
      'revision',
      'context',
      'submissionRevision',
      'predecessorId',
    });
    if (!_id(source['id']) ||
        !_id(source['device']) ||
        !_date(source['createdAt']) ||
        source['schemaVersion'] != 1 ||
        source['submissionRevision'] is! int ||
        source['submissionRevision'] < 1 ||
        source['submissionRevision'] > 1000000 ||
        source['document'] is! String ||
        !_hash(source['documentHash']) ||
        source['values'] is! Map ||
        source['context'] is! Map ||
        source['companyId'] != catalog['companyId'] ||
        !_id(source['jobId']) ||
        sources.containsKey(source['id'])) {
      _invalid();
    }
    final context = jobContext(catalog, source['jobId'] as String);
    if (canonical(source['context']) != canonical(context) ||
        source['equipmentId'] != context['equipmentId'] ||
        source['snapshotHash'] != context['snapshotHash'] ||
        source['revision'] != context['revision']) {
      _invalid();
    }
    try {
      final bytes = base64Decode(source['document'] as String);
      if (bytes.isEmpty ||
          bytes.length > 16 * 1024 * 1024 ||
          digest(bytes) != source['documentHash']) {
        _invalid();
      }
      final values = _map(source['values']);
      if (incompleteJob({
            for (final entry in values.entries) entry.key: [entry.value],
          }, context) !=
          null) {
        _invalid();
      }
    } on ManualFaultIntakeFailure {
      rethrow;
    } catch (_) {
      _invalid();
    }
    sources[source['id'] as String] = source;
  }
  for (final receipt in receipts) {
    _shape(receipt, {
      'id',
      'submissionId',
      'submissionHash',
      'decision',
      'reason',
      'reviewedAt',
      'reviewedBy',
      'reviewerDevice',
      'values',
    });
    final source = sources[receipt['submissionId']];
    if (source == null ||
        !_id(receipt['id']) ||
        !receiptIds.add(receipt['id'] as String) ||
        decisions.containsKey(receipt['submissionId']) ||
        receipt['submissionHash'] != contentHash(source) ||
        !{'approved', 'returned'}.contains(receipt['decision']) ||
        receipt['reason'] is! String ||
        (receipt['reason'] as String).length > 10000 ||
        (receipt['decision'] == 'returned' &&
            (receipt['reason'] as String).trim().isEmpty) ||
        !_date(receipt['reviewedAt']) ||
        !_id(receipt['reviewerDevice']) ||
        receipt['reviewedBy'] != catalog['coordinatorName'] ||
        canonical(receipt['values']) != canonical(source['values'])) {
      _invalid();
    }
    decisions[receipt['submissionId'] as String] = receipt;
  }
  return _Sources(sources, decisions);
}

ManualFaultOrigin _originFor(
  Json source,
  Json? receipt,
  String kind,
  String? itemId,
  String observation,
) {
  final context = _map(source['context']);
  final job = _map(context['job']);
  final suffix = switch (kind) {
    'item' =>
      (context['checklistSnapshot']['items'] as List).singleWhere(
            (row) => row['id'] == itemId,
          )['label']
          as String,
    'note' => 'Saved inspection notes',
    _ => 'Saved inspection submission',
  };
  return ManualFaultOrigin.fromJson({
    'version': 1,
    'kind': kind,
    'submissionId': source['id'],
    'submissionHash': contentHash(source),
    'documentHash': source['documentHash'],
    'jobId': source['jobId'],
    'submissionRevision': source['submissionRevision'],
    'snapshotHash': source['snapshotHash'],
    'itemId': itemId,
    'observation': observation,
    'receiptId': observation == 'pending' ? null : receipt?['id'],
    'receiptHash': observation == 'pending' ? null : contentHash(receipt),
    'label':
        '${job['title']} · version ${source['submissionRevision']} · $suffix',
  });
}

/// Complete reusable recovery validation. Unknown versions and damaged history
/// throw before any write. Pending observations deliberately stay historical
/// when a submission receives an immutable review after the command was frozen.
ManualFaultIntakeState validateManualFaultIntake({
  required Json settings,
  required List<Json> events,
  required Json? catalog,
  required String deviceId,
  required List<Json> submissions,
  required List<Json> receipts,
}) {
  final ownEvents = events
      .where((event) => event['kind'] == manualFaultReportedEvent)
      .toList();
  final raw = settings[manualFaultIntakeSetting];
  if (raw == null && !settings.containsKey(manualFaultIntakeSetting)) {
    if (ownEvents.isNotEmpty) _invalid();
    return ManualFaultIntakeState.empty();
  }
  final data = _map(raw);
  _version(data);
  _shape(data, {'version', 'pending', 'receipts'});
  if (data['pending'] is! List ||
      (data['pending'] as List).length > 1 ||
      data['receipts'] is! List ||
      (data['receipts'] as List).length > manualFaultRecordLimit ||
      utf8.encode(canonical(data)).length > manualFaultStateByteLimit ||
      catalog == null) {
    _invalid();
  }
  validateCatalog(catalog);
  if (!_id(deviceId)) _invalid();
  final sources = _sourceIndex(catalog, submissions, receipts);
  final pending = [
    for (final row in data['pending'] as List)
      FrozenManualFaultCommand.fromJson(_map(row)),
  ];
  final finalized = [
    for (final row in data['receipts'] as List)
      ManualFaultReceipt.fromJson(_map(row)),
  ];
  final commands = <String>{};
  void validateCommand(FrozenManualFaultCommand command) {
    if (!commands.add(command.id) ||
        command.companyId != catalog['companyId'] ||
        command.deviceId != deviceId ||
        !(catalog['equipment'] as List).any(
          (row) => row['id'] == command.equipmentId,
        )) {
      _invalid();
    }
    final origin = command.origin;
    if (origin == null) return;
    final source = sources.submissions[origin.submissionId];
    if (source == null || source['equipmentId'] != command.equipmentId) {
      _invalid();
    }
    final decision = sources.receipts[origin.submissionId];
    if (origin.observation != ManualFaultObservation.pending &&
        (decision == null ||
            decision['reviewerDevice'] != deviceId ||
            decision['id'] != origin.receiptId ||
            contentHash(decision) != origin.receiptHash ||
            decision['decision'] != origin.observation.name)) {
      _invalid();
    }
    try {
      final expected = _originFor(
        source,
        decision,
        origin.kind.name,
        origin.itemId,
        origin.observation.name,
      );
      if (canonical(expected.toJson()) != canonical(origin.toJson())) {
        _invalid();
      }
    } on ManualFaultIntakeFailure {
      rethrow;
    } catch (_) {
      _invalid();
    }
  }

  for (final command in pending) {
    validateCommand(command);
  }
  final expectedEvents = <String, ManualFaultReceipt>{};
  for (final receipt in finalized) {
    validateCommand(receipt.command);
    expectedEvents[receipt.commandId] = receipt;
  }
  final seenEvents = <String>{};
  for (final event in ownEvents) {
    final receipt = ManualFaultReceipt.fromJson(_map(event['payload']));
    final expected = expectedEvents[receipt.commandId];
    if (!seenEvents.add(receipt.commandId) ||
        expected == null ||
        canonical(receipt.toJson()) != canonical(expected.toJson())) {
      _invalid();
    }
  }
  if (seenEvents.length != expectedEvents.length) _invalid();
  return ManualFaultIntakeState._(data);
}
