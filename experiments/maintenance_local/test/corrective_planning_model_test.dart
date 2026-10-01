import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/corrective_planning.dart';
import 'package:maintenance_local/maintenance_domain.dart';
import 'package:maintenance_local/manual_fault_intake.dart';
import 'package:maintenance_local/model.dart';

const _device = 'synthetic-office';
const _time = '2026-10-01T12:00:00.000Z';
String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Json _rehash(Json value) {
  final clean = {...value}..remove('hash');
  return {...clean, 'hash': contentHash(clean)};
}

Matcher _failure([String? code]) => throwsA(
  isA<CorrectivePlanningFailure>().having(
    (e) => e.code,
    'code',
    code ?? isNotEmpty,
  ),
);

class _Fixture {
  _Fixture() {
    catalog = makeCatalog(
      id: 'company-a',
      name: 'Synthetic company',
      coordinatorName: 'Office',
    );
    equipment = makeEquipment(
      id: 'engine-a',
      name: 'Synthetic engine',
      serial: 'A1',
    );
    catalog['equipment'] = [
      equipment,
      makeEquipment(id: 'engine-b', name: 'Other engine'),
    ];
    final template = makeTemplate(
      id: 'template-a',
      title: 'Inspection',
      items: [
        {'id': 'guard', 'label': 'Guard', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored'},
    );
    catalog['templates'] = [template];
    catalog['jobs'] = [
      makeJob(
        id: 'inspection-job',
        title: 'Existing inspection',
        equipment: equipment,
        template: template,
      ),
    ];
    manualReceipts = [
      for (final n in [1, 2, 3, 4])
        ManualFaultReceipt.create(
          FrozenManualFaultCommand.create(
            id: _uuid(n),
            companyId: 'company-a',
            deviceId: _device,
            equipmentId: n == 4 ? 'engine-b' : 'engine-a',
            description: 'Synthetic fault $n',
            severity: ManualFaultSeverity.normal,
            createdAt: _time,
          ),
          reportedAt: _time,
        ),
    ];
    manual = validateManualFaultIntake(
      settings: {
        manualFaultIntakeSetting: {
          'version': 1,
          'pending': <Json>[],
          'receipts': manualReceipts.map((r) => r.toJson()).toList(),
        },
      },
      events: [
        for (final r in manualReceipts)
          {'kind': manualFaultReportedEvent, 'payload': r.toJson()},
      ],
      catalog: catalog,
      deviceId: _device,
      submissions: [],
      receipts: [],
    );
  }
  late Json catalog, equipment;
  late List<ManualFaultReceipt> manualReceipts;
  late ManualFaultIntakeState manual;
  CorrectiveFaultReference ref(int n) =>
      CorrectiveFaultReference.fromRecord(manualReceipts[n - 1].record);
  FrozenCorrectivePlanningCommand create({
    int id = 100,
    List<int> faults = const [],
    String title = 'Plan repair',
    String description = 'Inspect and diagnose.',
  }) => FrozenCorrectivePlanningCommand.createDraft(
    id: _uuid(id),
    companyId: 'company-a',
    deviceId: _device,
    equipmentSnapshot: equipment,
    title: title,
    description: description,
    faults: faults.map(ref).toList(),
    createdAt: _time,
  );
  FrozenCorrectivePlanningCommand edit(
    CorrectiveWorkDraft draft, {
    int id = 101,
    int? revision,
    String? hash,
  }) => FrozenCorrectivePlanningCommand.editDraft(
    id: _uuid(id),
    companyId: 'company-a',
    deviceId: _device,
    draftId: draft.id,
    equipmentId: draft.equipmentId,
    expectedRevision: revision ?? draft.revision,
    expectedDraftHash: hash ?? draft.hash,
    title: 'Revised planning title',
    description: 'Check the retained evidence before repair.',
    createdAt: '2026-09-30T11:00:00.000Z',
  );
  FrozenCorrectivePlanningCommand link(
    CorrectiveWorkDraft draft,
    List<int> faults, {
    int id = 102,
  }) => FrozenCorrectivePlanningCommand.linkFaults(
    id: _uuid(id),
    companyId: 'company-a',
    deviceId: _device,
    draftId: draft.id,
    equipmentId: draft.equipmentId,
    expectedRevision: draft.revision,
    expectedDraftHash: draft.hash,
    faults: faults.map(ref).toList(),
    createdAt: _time,
  );
  CorrectivePlanningReceipt apply(
    FrozenCorrectivePlanningCommand command, {
    CorrectivePlanningState? state,
    String time = _time,
  }) => applyCorrectivePlanningCommand(
    state: state ?? CorrectivePlanningState.empty(),
    command: command,
    catalog: catalog,
    deviceId: _device,
    manualFaultHistory: manual,
    recordedAt: time,
  );
  Json ledger(
    List<CorrectivePlanningReceipt> receipts, {
    List<FrozenCorrectivePlanningCommand> pending = const [],
  }) => {
    'version': 1,
    'pending': pending.map((c) => c.toJson()).toList(),
    'receipts': receipts.map((r) => r.toJson()).toList(),
  };
  List<Json> events(List<CorrectivePlanningReceipt> receipts) => [
    for (final r in receipts)
      {'kind': correctivePlanningRecordedEvent, 'payload': r.toJson()},
  ];
  CorrectivePlanningState validate(
    List<CorrectivePlanningReceipt> receipts, {
    List<FrozenCorrectivePlanningCommand> pending = const [],
    List<Json>? ownEvents,
  }) => validateCorrectivePlanning(
    settings: {correctivePlanningSetting: ledger(receipts, pending: pending)},
    events: ownEvents ?? events(receipts),
    catalog: catalog,
    deviceId: _device,
    manualFaultHistory: manual,
    databaseVersion: 3,
  );
}

void main() {
  test(
    'schema2 without planning and accepted legacy null-company state remain empty',
    () {
      for (final version in [0, 1, 2]) {
        final state = validateCorrectivePlanning(
          settings: {},
          events: [],
          catalog: null,
          deviceId: _device,
          manualFaultHistory: ManualFaultIntakeState.empty(),
          databaseVersion: version,
        );
        expect(state.drafts, isEmpty);
        expect(state.pending, isEmpty);
      }
    },
  );
  test(
    'planning is prohibited in schema2 or legacy schema and future schema is refused',
    () {
      final fixture = _Fixture();
      for (final version in [0, 1, 2, 4]) {
        expect(
          () => validateCorrectivePlanning(
            settings: {
              correctivePlanningSetting: fixture.ledger(
                [],
                pending: [fixture.create()],
              ),
            },
            events: [],
            catalog: version < 2 ? null : fixture.catalog,
            deviceId: _device,
            manualFaultHistory: fixture.manual,
            databaseVersion: version,
          ),
          _failure(),
        );
      }
    },
  );
  test(
    'schema3 requires nonempty planning ledger and refuses event-only state',
    () {
      final f = _Fixture();
      expect(() => f.validate([]), _failure('invalid_state'));
      expect(
        () => validateCorrectivePlanning(
          settings: {},
          events: [],
          catalog: f.catalog,
          deviceId: _device,
          manualFaultHistory: f.manual,
          databaseVersion: 3,
        ),
        _failure('invalid_state'),
      );
      expect(
        () => validateCorrectivePlanning(
          settings: {},
          events: f.events([f.apply(f.create())]),
          catalog: f.catalog,
          deviceId: _device,
          manualFaultHistory: f.manual,
          databaseVersion: 2,
        ),
        _failure('invalid_state'),
      );
    },
  );
  test('unsupported ledger and command versions refuse explicitly', () {
    final f = _Fixture();
    final command = f.create().toJson()..['version'] = 2;
    expect(
      () => FrozenCorrectivePlanningCommand.fromJson(_rehash(command)),
      _failure('unsupported_version'),
    );
    expect(
      () => validateCorrectivePlanning(
        settings: {
          correctivePlanningSetting: {
            'version': 2,
            'pending': [],
            'receipts': [],
          },
        },
        events: [],
        catalog: f.catalog,
        deviceId: _device,
        manualFaultHistory: f.manual,
        databaseVersion: 3,
      ),
      _failure('unsupported_version'),
    );
  });
  test(
    'standalone corrective draft does not enter inspection catalog or change fault history',
    () {
      final f = _Fixture();
      final catalogBefore = canonical(f.catalog),
          manualBefore = canonical(f.manual.toJson());
      final receipt = f.apply(
        f.create(
          title: '  Diagnose leak  ',
          description: '  Find its source.  ',
        ),
      );
      final state = f.validate([receipt]);
      expect(state.drafts.single.id, 'corrective-${_uuid(100)}');
      expect(state.drafts.single.kind, 'corrective');
      expect(state.drafts.single.state, 'draft');
      expect(state.drafts.single.revision, 1);
      expect(state.drafts.single.faults, isEmpty);
      expect(state.drafts.single.title, 'Diagnose leak');
      expect(state.drafts.single.description, 'Find its source.');
      expect(canonical(f.catalog), catalogBefore);
      expect(canonical(f.manual.toJson()), manualBefore);
    },
  );
  test(
    'multi-fault creation canonicalizes selection order and derives all associations',
    () {
      final f = _Fixture();
      final one = f.create(faults: [3, 1, 2]),
          two = f.create(faults: [2, 3, 1]);
      expect(one.hash, two.hash);
      final receipt = f.apply(one), state = f.validate([f.apply(one)]);
      expect(receipt.draft.faults.map((r) => r.faultId), [
        _uuid(1),
        _uuid(2),
        _uuid(3),
      ]);
      for (final n in [1, 2, 3]) {
        expect(state.draftForFault(_uuid(n))!.id, receipt.draft.id);
        expect(
          f.manualReceipts[n - 1].record.status,
          manualFaultReportedStatus,
        );
      }
    },
  );
  test(
    'empty planning description is valid; duplicate selected fault identities are refused',
    () {
      final f = _Fixture();
      expect(f.apply(f.create(description: '')).draft.description, '');
      expect(() => f.create(faults: [1, 1]), _failure('invalid_state'));
      final draft = f.apply(f.create()).draft;
      expect(() => f.link(draft, []), _failure('invalid_state'));
      expect(() => f.link(draft, [1, 1]), _failure('invalid_state'));
      final changedHash = CorrectiveFaultReference.fromJson({
        'faultId': _uuid(1),
        'faultRecordHash': contentHash('different record under the same ID'),
      });
      expect(
        () => FrozenCorrectivePlanningCommand.createDraft(
          id: _uuid(100),
          companyId: 'company-a',
          deviceId: _device,
          equipmentSnapshot: f.equipment,
          title: 'Plan repair',
          description: '',
          faults: [f.ref(1), changedHash],
          createdAt: _time,
        ),
        _failure('invalid_state'),
      );
      final reversed = f.create(faults: [1, 2]).toJson();
      reversed['faults'] = (reversed['faults'] as List).reversed.toList();
      expect(
        () => FrozenCorrectivePlanningCommand.fromJson(_rehash(reversed)),
        _failure('invalid_state'),
      );
    },
  );
  test(
    'scope edit preserves identity equipment and associations despite clock rollback',
    () {
      final f = _Fixture(), first = _Fixture();
      final initial = f.apply(f.create(faults: [1]));
      final edit = f.apply(
        f.edit(initial.draft),
        state: f.validate([initial]),
        time: '2026-09-29T01:00:00.000Z',
      );
      final state = f.validate([initial, edit]);
      final draft = state.drafts.single;
      expect(draft.revision, 2);
      expect(draft.title, 'Revised planning title');
      expect(draft.equipmentSnapshot, initial.draft.equipmentSnapshot);
      expect(draft.createdAt, initial.draft.createdAt);
      expect(draft.updatedAt, '2026-09-29T01:00:00.000Z');
      expect(
        draft.faults.single.toJson(),
        initial.draft.faults.single.toJson(),
      );
      expect(canonical(f.manual.toJson()), canonical(first.manual.toJson()));
    },
  );
  test(
    'atomic link batch increments revision while retaining scope and original links',
    () {
      final f = _Fixture();
      final first = f.apply(f.create(faults: [1]));
      final link = f.apply(
        f.link(first.draft, [3, 2]),
        state: f.validate([first]),
      );
      final draft = f.validate([first, link]).drafts.single;
      expect(draft.revision, 2);
      expect(draft.title, first.draft.title);
      expect(draft.description, first.draft.description);
      expect(draft.faults.map((r) => r.faultId), [
        _uuid(1),
        _uuid(2),
        _uuid(3),
      ]);
    },
  );
  test(
    'several standalone drafts may share equipment without sharing fault associations',
    () {
      final f = _Fixture();
      final first = f.apply(f.create(faults: [1]));
      final second = f.apply(
        f.create(id: 105, faults: [2]),
        state: f.validate([first]),
      );
      final state = f.validate([first, second]);
      expect(state.drafts, hasLength(2));
      expect(state.draftForFault(_uuid(1))!.id, first.draft.id);
      expect(state.draftForFault(_uuid(2))!.id, second.draft.id);
    },
  );
  test(
    'new UUID cannot repeat same-target link or reassign an existing association',
    () {
      final f = _Fixture();
      final first = f.apply(f.create(faults: [1])),
          state = f.validate([
            f.apply(f.create(faults: [1])),
          ]);
      expect(
        () => f.apply(f.link(first.draft, [1]), state: state),
        _failure('already_linked'),
      );
      expect(
        () => f.apply(f.create(id: 106, faults: [1]), state: state),
        _failure('already_linked'),
      );
    },
  );
  test(
    'exact original link replay succeeds after later edits and preserves newer pending request',
    () {
      final f = _Fixture();
      final create = f.apply(f.create()),
          linkCommand = f.link(create.draft, [1]);
      final link = f.apply(linkCommand, state: f.validate([create]));
      final edit = f.apply(
        f.edit(link.draft),
        state: f.validate([create, link]),
      );
      final pending = f.edit(edit.draft, id: 107);
      final state = f.validate([create, link, edit], pending: [pending]);
      final before = canonical(state.toJson());
      final replay = f.apply(
        linkCommand,
        state: state,
        time: '2020-01-01T00:00:00Z',
      );
      expect(replay.toJson(), link.toJson());
      expect(canonical(state.toJson()), before);
      expect(state.pending.single.id, pending.id);
    },
  );
  test(
    'same UUID changed payload refuses before current revision or links',
    () {
      final f = _Fixture();
      final first = f.apply(f.create(faults: [1])),
          state = f.validate([
            f.apply(f.create(faults: [1])),
          ]);
      expect(
        () => f.apply(
          f.create(faults: [1], title: 'Different intent'),
          state: state,
        ),
        _failure('command_conflict'),
      );
      expect(state.receipts.single.hash, first.hash);
    },
  );
  test('both expected revision and hash must match current draft', () {
    final f = _Fixture(), first = _Fixture();
    final receipt = f.apply(f.create()),
        state = f.validate([f.apply(f.create())]);
    expect(
      () => f.apply(f.edit(receipt.draft, revision: 2), state: state),
      _failure('stale_revision'),
    );
    expect(
      () => f.apply(
        f.edit(receipt.draft, hash: contentHash('different')),
        state: state,
      ),
      _failure('stale_revision'),
    );
    expect(canonical(f.manual.toJson()), canonical(first.manual.toJson()));
  });
  test('inspection or absent draft cannot be targeted as corrective work', () {
    final f = _Fixture();
    final command = FrozenCorrectivePlanningCommand.editDraft(
      id: _uuid(110),
      companyId: 'company-a',
      deviceId: _device,
      draftId: 'inspection-job',
      equipmentId: 'engine-a',
      expectedRevision: 1,
      expectedDraftHash: contentHash((f.catalog['jobs'] as List).single),
      title: 'Repair',
      description: '',
      createdAt: _time,
    );
    expect(() => f.apply(command), _failure('draft_not_found'));
  });
  test(
    'cross-company office equipment and missing or changed fault bindings refuse',
    () {
      final f = _Fixture();
      for (final mutation in <String, dynamic>{
        'companyId': 'company-b',
        'deviceId': 'other-office',
        'equipmentId': 'missing-engine',
      }.entries) {
        final raw = f.create().toJson()..[mutation.key] = mutation.value;
        if (mutation.key == 'equipmentId') {
          raw['equipmentSnapshot']['id'] = mutation.value;
        }
        final command = FrozenCorrectivePlanningCommand.fromJson(_rehash(raw));
        expect(() => f.apply(command), _failure());
      }
      for (final ref in [
        CorrectiveFaultReference.fromJson({
          'faultId': _uuid(800),
          'faultRecordHash': contentHash('missing'),
        }),
        CorrectiveFaultReference.fromJson({
          'faultId': _uuid(1),
          'faultRecordHash': contentHash('changed'),
        }),
      ]) {
        final command = FrozenCorrectivePlanningCommand.createDraft(
          id: _uuid(111),
          companyId: 'company-a',
          deviceId: _device,
          equipmentSnapshot: f.equipment,
          title: 'Repair',
          description: '',
          faults: [ref],
          createdAt: _time,
        );
        expect(() => f.apply(command), _failure('invalid_fault'));
      }
    },
  );
  test(
    'mixed-equipment and partially already-linked batches fail without any partial effect',
    () {
      final f = _Fixture();
      final first = f.apply(f.create(faults: [1])),
          state = f.validate([
            f.apply(f.create(faults: [1])),
          ]);
      final before = canonical(state.toJson());
      expect(
        () => f.apply(f.link(first.draft, [2, 4]), state: state),
        _failure('invalid_fault'),
      );
      expect(
        () => f.apply(f.link(first.draft, [2, 1]), state: state),
        _failure('already_linked'),
      );
      expect(canonical(state.toJson()), before);
      expect(state.draftForFault(_uuid(2)), isNull);
    },
  );
  test('unreported pending manual fault is never a link source', () {
    final f = _Fixture();
    final pendingFault = FrozenManualFaultCommand.create(
      id: _uuid(9),
      companyId: 'company-a',
      deviceId: _device,
      equipmentId: 'engine-a',
      description: 'Unreported',
      severity: ManualFaultSeverity.normal,
      createdAt: _time,
    );
    final history = validateManualFaultIntake(
      settings: {
        manualFaultIntakeSetting: {
          'version': 1,
          'pending': [pendingFault.toJson()],
          'receipts': <Json>[],
        },
      },
      events: [],
      catalog: f.catalog,
      deviceId: _device,
      submissions: [],
      receipts: [],
    );
    expect(
      () => applyCorrectivePlanningCommand(
        state: CorrectivePlanningState.empty(),
        command: f.create(faults: [1]),
        catalog: f.catalog,
        deviceId: _device,
        manualFaultHistory: history,
        recordedAt: _time,
      ),
      _failure('invalid_fault'),
    );
  });
  test(
    'accepted equipment spelling and later labels do not rewrite frozen context',
    () {
      final f = _Fixture();
      f.equipment['name'] = '  Accepted existing name  ';
      f.equipment['serial'] = '  Existing serial  ';
      final first = f.apply(f.create(faults: [1]));
      f.equipment['name'] = 'Later current label';
      f.equipment['serial'] = 'Later serial';
      final pending = f.link(first.draft, [2]);
      final state = f.validate([first], pending: [pending]);
      expect(
        state.drafts.single.equipmentSnapshot['name'],
        '  Accepted existing name  ',
      );
      expect(
        state.drafts.single.equipmentSnapshot['serial'],
        '  Existing serial  ',
      );
    },
  );
  test('input and nested getters are detached and lists are immutable', () {
    final f = _Fixture();
    final command = f.create(faults: [1]), before = command.toJson();
    f.equipment['name'] = 'Caller mutation';
    command.equipmentSnapshot!['name'] = 'Getter mutation';
    command.toJson()['faults'][0]['faultRecordHash'] = contentHash('mutation');
    expect(command.toJson(), before);
    expect(() => command.faults.clear(), throwsUnsupportedError);
    final receipt = f.apply(command), state = f.validate([f.apply(command)]);
    receipt.draft.equipmentSnapshot['serial'] = 'Mutation';
    state.toJson()['receipts'].clear();
    expect(state.receipts.single.toJson(), receipt.toJson());
    expect(() => state.drafts.clear(), throwsUnsupportedError);
  });
  test(
    'rehashing wrong draft kind state or unsupported operation does not legitimize it',
    () {
      final f = _Fixture(), first = _Fixture();
      final draft = f.apply(f.create()).draft;
      for (final mutation in {
        'kind': 'inspection',
        'state': 'approved',
        'revision': 0,
      }.entries) {
        final raw = draft.toJson()..[mutation.key] = mutation.value;
        expect(
          () => CorrectiveWorkDraft.fromJson(_rehash(raw)),
          _failure('invalid_state'),
        );
      }
      final raw = f.create().toJson()..['action'] = 'execute';
      expect(
        () => FrozenCorrectivePlanningCommand.fromJson(_rehash(raw)),
        _failure('invalid_state'),
      );
      expect(canonical(first.manual.toJson()), canonical(f.manual.toJson()));
    },
  );
  test('receipt result and previous revision bind exactly to frozen scope', () {
    final f = _Fixture();
    final receipt = f.apply(f.create(faults: [1]));
    final raw = receipt.toJson();
    raw['draft']['title'] = 'Forged result';
    raw['draft'] = _rehash(raw['draft'] as Json);
    expect(
      () => CorrectivePlanningReceipt.fromJson(_rehash(raw)),
      _failure('invalid_state'),
    );
  });
  test(
    'receipt chain cannot be reordered duplicated or branch from a stale predecessor',
    () {
      final f = _Fixture();
      final first = f.apply(f.create()),
          state = f.validate([f.apply(f.create())]);
      final edit = f.apply(f.edit(first.draft), state: state);
      expect(() => f.validate([edit, first]), _failure());
      expect(() => f.validate([first, first]), _failure('invalid_state'));
      final stale = CorrectivePlanningReceipt.create(
        f.edit(first.draft, id: 112),
        previousDraft: first.draft,
        recordedAt: _time,
      );
      expect(
        () => f.validate([first, edit, stale]),
        _failure('stale_revision'),
      );
    },
  );
  test(
    'every accepted command requires exactly one canonically identical planning event',
    () {
      final f = _Fixture(), receipt = _Fixture().apply(_Fixture().create());
      expect(
        () => f.validate([receipt], ownEvents: []),
        _failure('invalid_state'),
      );
      expect(
        () => f.validate(
          [receipt],
          ownEvents: [
            ...f.events([receipt]),
            ...f.events([receipt]),
          ],
        ),
        _failure('invalid_state'),
      );
      final other = f.apply(f.create(id: 113));
      expect(
        () => f.validate([receipt], ownEvents: f.events([other])),
        _failure('invalid_state'),
      );
      expect(
        f
            .validate(
              [receipt],
              ownEvents: [
                ...f.events([receipt]),
                {'kind': 'existing-inspection-event', 'payload': {}},
              ],
            )
            .drafts,
        hasLength(1),
      );
    },
  );
  test(
    'one durable pending command must apply to the current receipt-derived revision',
    () {
      final f = _Fixture();
      expect(f.validate([], pending: [f.create()]).pending, hasLength(1));
      expect(
        () => f.validate([], pending: [f.create(), f.create(id: 114)]),
        _failure('invalid_state'),
      );
      final first = f.apply(f.create()),
          edit = f.apply(
            f.edit(f.apply(f.create()).draft),
            state: f.validate([f.apply(f.create())]),
          );
      expect(
        () =>
            f.validate([first, edit], pending: [f.edit(first.draft, id: 115)]),
        _failure('stale_revision'),
      );
      expect(
        () => f.validate([first], pending: [first.command]),
        _failure('invalid_state'),
      );
      final state = f.validate([first], pending: [f.edit(first.draft)]);
      expect(
        () => f.apply(f.create(id: 116), state: state),
        _failure('pending_command'),
      );
    },
  );
  test(
    'title description record-count and ledger-size bounds reject unsupported input',
    () {
      final f = _Fixture();
      expect(
        f
            .create(
              title: List.filled(200, 't').join(),
              description: List.filled(10000, 'd').join(),
            )
            .description!
            .length,
        10000,
      );
      expect(
        () => f.create(title: List.filled(201, 't').join()),
        _failure('invalid_state'),
      );
      expect(
        () => f.create(description: List.filled(10001, 'd').join()),
        _failure('invalid_state'),
      );
      final receipt = f.apply(f.create());
      expect(
        () =>
            f.validate(List.filled(correctivePlanningRecordLimit + 1, receipt)),
        _failure('invalid_state'),
      );
      final huge = f.ledger([], pending: [f.create()]);
      huge['pending'][0]['description'] = List.filled(
        correctivePlanningStateByteLimit + 1,
        'x',
      ).join();
      expect(
        utf8.encode(canonical(huge)).length,
        greaterThan(correctivePlanningStateByteLimit),
      );
      expect(
        () => validateCorrectivePlanning(
          settings: {correctivePlanningSetting: huge},
          events: [],
          catalog: f.catalog,
          deviceId: _device,
          manualFaultHistory: f.manual,
          databaseVersion: 3,
        ),
        _failure('invalid_state'),
      );
    },
  );
}
