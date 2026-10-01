import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/model.dart';

const _device = '11111111-1111-4111-8111-111111111111';
const _commandId = '22222222-2222-4222-8222-222222222222';

class _Fixture {
  _Fixture({String unit = 'hours'}) {
    catalog = makeCatalog(
      id: 'synthetic-company',
      name: 'Synthetic company',
      coordinatorName: 'Synthetic coordinator',
    );
    final equipment = makeEquipment(
      id: 'synthetic-engine',
      name: 'Synthetic engine',
      meterUnit: unit,
    );
    final template = makeTemplate(
      id: 'synthetic-template',
      title: 'Synthetic checks',
      provenance: {'kind': 'manual-reference', 'reference': 'Synthetic page 7'},
      items: [
        {'id': 'guard', 'label': 'Guard condition', 'input_type': 'check'},
        {
          'id': 'pressure',
          'label': 'Pressure',
          'input_type': 'number',
          'unit': 'bar',
        },
      ],
    );
    final job = makeJob(
      id: 'synthetic-job',
      title: 'Synthetic inspection',
      equipment: equipment,
      template: template,
    );
    catalog['equipment'] = [equipment];
    catalog['templates'] = [template];
    catalog['jobs'] = [job];
    final context = jobContext(catalog, 'synthetic-job');
    final values = initialJobFields(context)
      ..addAll({
        'answer:guard': {'result': 'action', 'value': ''},
        'answer:pressure': {'result': 'pass', 'value': '0'},
        'meter': unit == 'none' ? null : 0,
        'notes': 'Synthetic saved note.',
        'photo': contentHash('synthetic photo'),
      });
    // Opaque synthetic bytes: pure reference validation checks their hash.
    // Native decoding/evidence are the existing backup boundary's responsibility.
    final bytes = utf8.encode('synthetic inspection bytes');
    submission = {
      'id': 'synthetic-submission',
      'companyId': catalog['companyId'],
      'jobId': 'synthetic-job',
      'device': _device,
      'createdAt': '2026-10-01T12:00:00.000Z',
      'document': base64Encode(bytes),
      'documentHash': digest(bytes),
      'values': values,
      'schemaVersion': 1,
      'equipmentId': 'synthetic-engine',
      'snapshotHash': context['snapshotHash'],
      'revision': 1,
      'context': context,
      'submissionRevision': 1,
      'predecessorId': null,
    };
  }
  late Json catalog, submission;
  Json review(String decision, {String time = '2026-10-01T12:30:00.000Z'}) => {
    'id': 'synthetic-$decision-receipt',
    'submissionId': submission['id'],
    'submissionHash': contentHash(submission),
    'decision': decision,
    'reason': decision == 'returned' ? 'Synthetic correction required.' : '',
    'reviewedAt': time,
    'reviewedBy': catalog['coordinatorName'],
    'reviewerDevice': _device,
    'values': submission['values'],
  };
  List<ManualFaultOrigin> origins([List<Json> receipts = const []]) =>
      manualFaultAvailableOrigins(
        catalog: catalog,
        equipmentId: 'synthetic-engine',
        submissions: [submission],
        receipts: receipts,
      );
  FrozenManualFaultCommand command({ManualFaultOrigin? origin}) =>
      FrozenManualFaultCommand.create(
        id: _commandId,
        companyId: catalog['companyId'] as String,
        deviceId: _device,
        equipmentId: 'synthetic-engine',
        description: 'Synthetic manual finding.',
        severity: ManualFaultSeverity.urgent,
        origin: origin,
        createdAt: '2026-10-01T13:00:00.000Z',
      );
  ManualFaultIntakeState validate(
    Json ledger, {
    List<Json> sourceReceipts = const [],
    List<Json> events = const [],
    List<Json>? submissions,
    String device = _device,
  }) => validateManualFaultIntake(
    settings: {manualFaultIntakeSetting: ledger},
    events: events,
    catalog: catalog,
    deviceId: device,
    submissions: submissions ?? [submission],
    receipts: sourceReceipts,
  );
}

Json _pending(FrozenManualFaultCommand command) => {
  'version': 1,
  'pending': [command.toJson()],
  'receipts': <Json>[],
};
Json _final(ManualFaultReceipt receipt) => {
  'version': 1,
  'pending': <Json>[],
  'receipts': [receipt.toJson()],
};
Json _event(ManualFaultReceipt receipt) => {
  'kind': manualFaultReportedEvent,
  'payload': receipt.toJson(),
};
Matcher get _invalid => throwsA(isA<ManualFaultIntakeFailure>());

void main() {
  test(
    'accepted source timestamp offsets retain their exact original hashes',
    () {
      final fixture = _Fixture();
      fixture.submission['createdAt'] = '2026-10-01T12:00:00+02:00';
      final sourceReceipt = fixture.review(
        'returned',
        time: '2026-10-01T12:30:00',
      );
      final origin = fixture.origins([sourceReceipt]).first;
      fixture.validate(
        _pending(fixture.command(origin: origin)),
        sourceReceipts: [sourceReceipt],
      );
      expect(origin.submissionHash, contentHash(fixture.submission));
      expect(origin.receiptHash, contentHash(sourceReceipt));
      expect(fixture.submission['createdAt'], '2026-10-01T12:00:00+02:00');
      expect(sourceReceipt['reviewedAt'], '2026-10-01T12:30:00');
    },
  );

  test(
    'accepted 1000-character step and 200-character job labels preserve all origins',
    () {
      final fixture = _Fixture();
      final equipment = (fixture.catalog['equipment'] as List).single as Json;
      final template = makeTemplate(
        id: 'synthetic-long-template',
        title: 'Long accepted labels',
        provenance: {'kind': 'company-authored'},
        items: [
          {
            'id': 'long-step',
            'label': List.filled(1000, 'x').join(),
            'input_type': 'check',
          },
        ],
      );
      final job = makeJob(
        id: 'synthetic-job',
        title: List.filled(200, 'j').join(),
        equipment: equipment,
        template: template,
      );
      fixture.catalog['jobs'] = [job];
      final context = jobContext(fixture.catalog, 'synthetic-job');
      final values = initialJobFields(context)
        ..addAll({
          'answer:long-step': {'result': 'action', 'value': ''},
          'meter': 0,
          'notes': 'Synthetic note',
          'photo': contentHash('synthetic photo'),
        });
      fixture.submission.addAll({
        'context': context,
        'snapshotHash': context['snapshotHash'],
        'values': values,
      });
      final choices = fixture.origins();
      expect(choices, hasLength(3));
      final step = choices.singleWhere(
        (origin) => origin.kind == ManualFaultOriginKind.item,
      );
      expect(step.label.length, greaterThan(1000));
      fixture.validate(_pending(fixture.command(origin: step)));
    },
  );

  test(
    'clock skew and corrected office clock preserve exact source and receipt identities',
    () {
      final fixture = _Fixture();
      fixture.submission['createdAt'] = '2030-10-01T12:00:00.000Z';
      final sourceReceipt = fixture.review(
        'approved',
        time: '2031-10-01T12:00:00.000Z',
      );
      final command = fixture.command(
        origin: fixture.origins([sourceReceipt]).first,
      );
      fixture.validate(_pending(command), sourceReceipts: [sourceReceipt]);
      final receipt = ManualFaultReceipt.create(
        command,
        reportedAt: '2020-10-01T12:00:00.000Z',
      );
      fixture.validate(
        _final(receipt),
        events: [_event(receipt)],
        sourceReceipts: [sourceReceipt],
      );
      expect(receipt.command.createdAt, '2026-10-01T13:00:00.000Z');
      expect(receipt.record.reportedAt, '2020-10-01T12:00:00.000Z');
    },
  );

  test(
    'missing namespace is empty, own orphan event and null namespace reject',
    () {
      final fixture = _Fixture();
      final receipt = ManualFaultReceipt.create(
        fixture.command(),
        reportedAt: '2026-10-01T13:01:00.000Z',
      );
      ManualFaultIntakeState run(Json settings, List<Json> events) =>
          validateManualFaultIntake(
            settings: settings,
            events: events,
            catalog: null,
            deviceId: _device,
            submissions: [],
            receipts: [],
          );
      expect(run({}, []).receipts, isEmpty);
      expect(() => run({}, [_event(receipt)]), _invalid);
      expect(() => run({manualFaultIntakeSetting: null}, []), _invalid);
    },
  );

  test(
    'unknown versions reject without interpreting or changing retained data',
    () {
      final fixture = _Fixture();
      final unknown = {'version': 2, 'future': 'Retain this opaque value'};
      final before = canonical(unknown);
      expect(
        () => fixture.validate(unknown),
        throwsA(
          isA<ManualFaultIntakeFailure>().having(
            (e) => e.code,
            'code',
            'unsupported_version',
          ),
        ),
      );
      expect(canonical(unknown), before);
    },
  );

  test(
    'frozen models and receipt results cannot change through nested getters',
    () {
      final fixture = _Fixture();
      final command = fixture.command(origin: fixture.origins().first);
      final receipt = ManualFaultReceipt.create(
        command,
        reportedAt: '2026-10-01T13:01:00.000Z',
      );
      final before = canonical(receipt.toJson());
      receipt.toJson()['command']['origin']['observation'] = 'approved';
      command.toJson()['description'] = 'Altered after freeze';
      expect(canonical(receipt.toJson()), before);
      expect(receipt.record.status, manualFaultReportedStatus);
      expect(receipt.record.commandId, command.id);
      expect(
        fixture
            .validate(_final(receipt), events: [_event(receipt)])
            .receipts
            .single
            .hash,
        receipt.hash,
      );
    },
  );

  test(
    'duplicate commands, missing or duplicate events and altered results reject',
    () {
      final fixture = _Fixture();
      final command = fixture.command();
      final receipt = ManualFaultReceipt.create(
        command,
        reportedAt: '2026-10-01T13:01:00.000Z',
      );
      expect(
        () => fixture.validate(
          {
            'version': 1,
            'pending': [command.toJson()],
            'receipts': [receipt.toJson()],
          },
          events: [_event(receipt)],
        ),
        _invalid,
      );
      expect(
        () => fixture.validate(
          {
            'version': 1,
            'pending': [],
            'receipts': [receipt.toJson(), receipt.toJson()],
          },
          events: [_event(receipt)],
        ),
        _invalid,
      );
      expect(() => fixture.validate(_final(receipt)), _invalid);
      expect(
        () => fixture.validate(
          _final(receipt),
          events: [_event(receipt), _event(receipt)],
        ),
        _invalid,
      );
      final altered = receipt.toJson();
      altered['record']['status'] = 'Corrective work complete';
      altered['record']['hash'] = contentHash(
        {...altered['record'] as Json}..remove('hash'),
      );
      altered['hash'] = contentHash({...altered}..remove('hash'));
      expect(
        () => fixture.validate(
          {
            'version': 1,
            'pending': [],
            'receipts': [altered],
          },
          events: [
            {'kind': manualFaultReportedEvent, 'payload': altered},
          ],
        ),
        _invalid,
      );
      final other = ManualFaultReceipt.create(
        command,
        reportedAt: '2026-10-01T13:02:00.000Z',
      );
      expect(
        () => fixture.validate(_final(receipt), events: [_event(other)]),
        _invalid,
      );
    },
  );

  test('historical pending observation survives a later approved receipt', () {
    final fixture = _Fixture();
    final command = fixture.command(origin: fixture.origins().last);
    final later = fixture.review('approved', time: '2026-10-01T13:30:00.000Z');
    final validated = fixture.validate(
      _pending(command),
      sourceReceipts: [later],
    );
    expect(
      validated.pending.single.origin!.observation,
      ManualFaultObservation.pending,
    );
    expect(validated.pending.single.origin!.receiptHash, isNull);
    expect(
      fixture.origins([later]).last.observation,
      ManualFaultObservation.approved,
    );
  });

  test(
    'approved and returned observations pin the referenced immutable receipt hash',
    () {
      for (final decision in ['approved', 'returned']) {
        final fixture = _Fixture();
        final sourceReceipt = fixture.review(decision);
        final origin = fixture
            .origins([sourceReceipt])
            .firstWhere((origin) => origin.kind == ManualFaultOriginKind.item);
        final command = fixture.command(origin: origin);
        expect(origin.receiptHash, contentHash(sourceReceipt));
        expect(
          fixture
              .validate(_pending(command), sourceReceipts: [sourceReceipt])
              .pending
              .single
              .origin!
              .receiptHash,
          origin.receiptHash,
        );
        expect(() => fixture.validate(_pending(command)), _invalid);
        final changedReceipt = {
          ...sourceReceipt,
          'reason': 'Different reviewed reason',
        };
        expect(
          () => fixture.validate(
            _pending(command),
            sourceReceipts: [changedReceipt],
          ),
          _invalid,
        );
      }
    },
  );

  test(
    'saved exact source references reject missing source, changed bytes, wrong equipment and device',
    () {
      final fixture = _Fixture();
      final command = fixture.command(origin: fixture.origins().first);
      expect(
        () => fixture.validate(_pending(command), submissions: []),
        _invalid,
      );
      expect(
        () => fixture.validate(
          _pending(command),
          submissions: [
            {
              ...fixture.submission,
              'document': base64Encode([9, 8, 7]),
            },
          ],
        ),
        _invalid,
      );
      expect(
        () => fixture.validate(_pending(command), device: 'other-office'),
        _invalid,
      );
      final badOrigin = command.origin!.toJson()
        ..['itemId'] = 'unsaved-draft-step'
        ..['kind'] = 'item';
      final forged = fixture.command(
        origin: ManualFaultOrigin.fromJson(badOrigin),
      );
      expect(() => fixture.validate(_pending(forged)), _invalid);
      expect(
        manualFaultAvailableOrigins(
          catalog: fixture.catalog,
          equipmentId: 'synthetic-engine',
          submissions: [],
          receipts: [],
        ),
        isEmpty,
      );
    },
  );

  test(
    'zero and unknown readings retain every selected meter unit without fault inference',
    () {
      for (final unit in maintenanceMeterUnits) {
        final fixture = _Fixture(unit: unit);
        final origins = fixture.origins();
        expect(origins, hasLength(4));
        final command = fixture.command(origin: origins[2]);
        fixture.validate(_pending(command));
        expect(fixture.submission['values']['unit'], unit);
        expect(
          fixture.submission['values']['meter'],
          unit == 'none' ? isNull : 0,
        );
        expect(fixture.submission['values']['answer:pressure']['value'], '0');
        expect(command.description, 'Synthetic manual finding.');
        expect(command.toJson().keys, isNot(contains('availability')));
      }
    },
  );
}
