import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/office_backup.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

import 'support/recovery_process_harness.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });

  late Directory root;
  final stores = <LabStore>[];
  Directory path(String name) => Directory('${root.path}/$name');

  Future<LabStore> open(String name, {bool maintenanceOnly = false}) async {
    final store = await LabStore.open(
      path(name),
      office: true,
      now: () => DateTime.utc(2026, 9, 30, 12),
      maintenanceOnly: maintenanceOnly,
    );
    stores.add(store);
    return store;
  }

  Future<void> close(LabStore store) async {
    await store.close();
    stores.remove(store);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'maintenance-restore-boundary-',
    );
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  Future<Json> manifest(Directory backup) async =>
      jsonDecode(await File('${backup.path}/manifest.json').readAsString())
          as Json;

  Future<Json> owner(Directory directory) async =>
      jsonDecode(
            await File(
              '${directory.path}/maintenance-local-owner.json',
            ).readAsString(),
          )
          as Json;

  Future<Json> inventory(Directory directory) async {
    final files = <String, dynamic>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final relative = entity.path.substring(directory.path.length + 1);
        files[relative] = digest(await entity.readAsBytes());
      }
    }
    return files;
  }

  String savedState(LabStore store) => canonical({
    'device': store.device,
    'workspace': store.workspace,
    'catalog': store.catalog,
    'activeJobId': store.activeJobId,
    'documents': {
      for (final row in store.db.select('SELECT id,bytes FROM documents'))
        row['id'] as String: digest(row['bytes'] as List<int>),
    },
    'submissions': store.submissions,
    'receipts': store.receipts,
    'phones': DeviceAuthority(store).phones,
    'invites': store.db
        .select('SELECT * FROM invites')
        .map((row) => row.values.toList())
        .toList(),
  });

  Future<Json> prepare(LabStore office, String label) async {
    final equipment = await office.addEquipment(
      name: 'Synthetic boundary equipment $label',
      serial: 'RESTORE-BOUNDARY-$label',
      meterUnit: 'hours',
    );
    final template = await office.publishChecklist(
      title: 'Synthetic boundary checklist $label',
      items: [
        {
          'id': 'precheck',
          'label': 'Inspect the synthetic guard',
          'input_type': 'check',
        },
      ],
      provenance: {'kind': 'company-authored'},
    );
    return office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: template['id'] as String,
      title: 'Synthetic boundary inspection $label',
    );
  }

  Future<Json> submit(LabStore office, String jobId, List<int> photo) async {
    await office.update({
      'answer:precheck': {'result': 'action', 'value': ''},
      'meter': 0,
      'notes': 'Synthetic guard finding recorded before backup.',
    }, jobId: jobId);
    await office.attach(photo, jobId: jobId);
    return office.submit(jobId: jobId);
  }

  Matcher wrongFormat() => throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'maintenance-only rejection',
      contains('Use a Local Maintenance office backup'),
    ),
  );

  test(
    'Maintenance-only inspection and restore reject a valid synthetic legacy backup without publishing or changing work',
    () async {
      final legacy = await open('synthetic-legacy-source');
      await legacy.createWorkspace();
      final legacyIdentity = await OfficeIdentity.load(legacy);
      await legacy.update({
        'fluid': 'pass',
        'guards': 'attention',
        'meter': 0,
        'notes':
            'Synthetic legacy fixture; no real backup or device was accessed.',
      });
      await legacy.attach([11, 22, 33, 44]);
      final legacySubmission = await legacy.submit();
      await legacy.decide(legacySubmission['id'] as String, approve: true);
      final legacyBackup = path('synthetic-legacy-backup');
      await OfficeBackup.create(legacy, legacyBackup);
      final legacyManifest = await manifest(legacyBackup);
      expect(legacyManifest['format'], 'vortice-sync-lab-office');
      expect(legacyManifest['version'], 1);
      // Prove this is a valid adopted fixture, rather than a damaged input that
      // could make a missing maintenance boundary appear to work.
      final compatible = await OfficeBackup.inspect(legacyBackup);
      expect(compatible.device, legacy.device);
      expect(compatible.fingerprint, legacyIdentity.fingerprint);
      expect(compatible.submissions, 1);
      expect(compatible.receipts, 1);

      final current = await open(
        'synthetic-current-maintenance-work',
        maintenanceOnly: true,
      );
      await current.createCompany('Synthetic current maintenance company');
      final currentIdentity = await OfficeIdentity.load(current);
      final job = await prepare(current, 'retained');
      await submit(current, job['id'] as String, [55, 66, 77]);
      final beforeLegacy = savedState(legacy);
      final beforeCurrent = savedState(current);
      final beforeBackup = await inventory(legacyBackup);
      final destination = path('rejected-maintenance-office');

      await expectLater(
        OfficeBackup.inspect(
          legacyBackup,
          requiredFormat: OfficeBackupFormat.maintenance,
        ),
        wrongFormat(),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          OfficeBackup.restore(
            legacyBackup,
            destination,
            expectedFingerprint: legacyIdentity.fingerprint,
            requiredFormat: OfficeBackupFormat.maintenance,
          ),
          wrongFormat(),
        );
        expect(await destination.exists(), isFalse);
        expect(savedState(legacy), beforeLegacy);
        expect(savedState(current), beforeCurrent);
        expect(await inventory(legacyBackup), beforeBackup);
        expect(
          (await root.list().toList()).where(
            (entity) => entity.path.contains('.office-recovery-'),
          ),
          isEmpty,
        );
      }
      // Exercise both ordinary CLI entry points: a format gate that only the
      // low-level adopted API uses would leave the product restore path open.
      for (final command in [
        ['verify', legacyBackup.path],
        [
          'restore',
          legacyBackup.path,
          destination.path,
          legacyIdentity.fingerprint,
        ],
      ]) {
        final rejected = await Process.run(RecoveryProcess.dart, [
          '--suppress-analytics',
          'run',
          'tool/office_recovery.dart',
          ...command,
        ]);
        expect(rejected.exitCode, 1, reason: rejected.stderr.toString());
        expect(rejected.stdout.toString(), isEmpty);
        expect(
          rejected.stderr.toString(),
          contains('Use a Local Maintenance office backup'),
        );
        expect(await destination.exists(), isFalse);
        expect(savedState(current), beforeCurrent);
        expect(await inventory(legacyBackup), beforeBackup);
      }
      expect(
        (await OfficeIdentity.load(current)).fingerprint,
        currentIdentity.fingerprint,
      );

      // Explicit adopted API compatibility remains available for isolated
      // fixtures while the ordinary maintenance entry points opt into the fence.
      await OfficeBackup.restore(
        legacyBackup,
        path('synthetic-adopted-fixture-copy'),
        expectedFingerprint: legacyIdentity.fingerprint,
      );
      final fixtureCopy = await open('synthetic-adopted-fixture-copy');
      expect(fixtureCopy.realWorkspace, isFalse);
      expect(fixtureCopy.catalog, isNull);
      expect(fixtureCopy.device, legacy.device);
      expect(await fixtureCopy.fields(), await legacy.fields());
      expect(fixtureCopy.receipts, legacy.receipts);
      expect(await inventory(legacyBackup), beforeBackup);
      expect(savedState(current), beforeCurrent);
    },
    skip: !Platform.isLinux,
  );

  test(
    'Maintenance-only restore accepts a real version-two backup with frozen jobs, history, evidence, and authority fences',
    () async {
      final office = await open(
        'synthetic-maintenance-source',
        maintenanceOnly: true,
      );
      await office.createCompany(
        'Synthetic restore boundary company',
        coordinatorName: 'Synthetic restore coordinator',
      );
      final identity = await OfficeIdentity.load(office);
      final first = await prepare(office, 'A');
      final second = await prepare(office, 'B');
      final firstId = first['id'] as String, secondId = second['id'] as String;
      final approvedVersion = await submit(office, firstId, [1, 3, 5, 7]);
      final approval = await office.decide(
        approvedVersion['id'] as String,
        approve: true,
      );
      final returnedVersion = await submit(office, secondId, [2, 4, 6, 8]);
      final returned = await office.decide(
        returnedVersion['id'] as String,
        approve: false,
        reason: 'Synthetic follow-up required.',
      );
      await office.update({
        'notes': 'Synthetic latest draft after review.',
      }, jobId: secondId);
      await office.attach([9, 10, 11, 12], jobId: secondId);
      office.selectJob(firstId);

      final authority = DeviceAuthority(office);
      final tokens = {
        'synthetic-active-phone': secret(),
        'synthetic-pending-phone': secret(),
        'synthetic-revoked-phone': secret(),
      };
      for (final entry in tokens.entries) {
        authority.request({
          'device': entry.key,
          'label': entry.key,
          'token': entry.value,
          'invitation': authority.invite(),
        });
      }
      authority.confirm('synthetic-active-phone');
      authority.revoke('synthetic-revoked-phone');
      authority.invite();
      final backup = path('synthetic-maintenance-backup');
      await OfficeBackup.create(office, backup);
      final realManifest = await manifest(backup);
      expect(realManifest['format'], 'maintenance-local-office');
      expect(realManifest['version'], 2);
      final beforeBackup = await inventory(backup);
      final checked = await OfficeBackup.inspect(
        backup,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(checked.device, office.device);
      expect(checked.fingerprint, identity.fingerprint);
      expect(checked.submissions, 2);
      expect(checked.receipts, 2);
      expect(checked.evidenceFiles, 3);
      expect(checked.phonesToReconfirm, 2);
      expect(checked.revokedPhones, 1);
      expect(checked.invitationsToDiscard, 4);
      final beforeSource = savedState(office);

      final result = await OfficeBackup.restore(
        backup,
        path('synthetic-restored-maintenance'),
        expectedFingerprint: identity.fingerprint,
        requiredFormat: OfficeBackupFormat.maintenance,
      );
      expect(result.phonesToReconfirm, 2);
      expect(result.invitationsDiscarded, 4);
      final restored = await open(
        'synthetic-restored-maintenance',
        maintenanceOnly: true,
      );
      expect(restored.realWorkspace, isTrue);
      expect(await owner(restored.root), {
        'application': 'org.vortice.next.maintenance_local',
        'role': 'linux-office',
        'version': 1,
      });
      expect(
        restored.setting('localMaintenanceApplication'),
        'org.vortice.next.maintenance_local',
      );
      expect(restored.setting('localMaintenanceRole'), 'linux-office');
      expect(restored.device, office.device);
      expect(restored.catalog, office.catalog);
      expect(
        restored.catalog!['company'],
        'Synthetic restore boundary company',
      );
      expect(
        restored.catalog!['coordinatorName'],
        'Synthetic restore coordinator',
      );
      expect(restored.activeJobId, firstId);
      expect(restored.jobs.map((job) => job['id']), [firstId, secondId]);
      for (final id in [firstId, secondId]) {
        expect(restored.jobContextFor(id), office.jobContextFor(id));
        expect(
          await restored.fields(jobId: id),
          await office.fields(jobId: id),
        );
        expect(
          digest(restored.documentFor(id)!),
          digest(office.documentFor(id)!),
        );
      }
      expect(restored.submissions, office.submissions);
      expect(restored.receipts, [approval, returned]);
      expect(
        await restored.requiredEvidence(),
        await office.requiredEvidence(),
      );
      expect(
        await restored.evidence.manifest(),
        await office.evidence.manifest(),
      );
      expect(
        (await OfficeIdentity.load(restored)).fingerprint,
        identity.fingerprint,
      );
      final restoredAuthority = DeviceAuthority(restored);
      expect(restoredAuthority.phones.map((phone) => phone['status']), [
        'pending',
        'pending',
        'revoked',
      ]);
      for (final token in tokens.values) {
        expect(
          () => restoredAuthority.authenticate('Bearer $token'),
          throwsStateError,
        );
      }
      expect(restored.db.select('SELECT * FROM invites'), isEmpty);
      restoredAuthority.confirm('synthetic-active-phone');
      expect(
        restoredAuthority.authenticate(
          'Bearer ${tokens['synthetic-active-phone']}',
        ),
        'synthetic-active-phone',
      );
      restoredAuthority.confirm('synthetic-revoked-phone');
      expect(
        () => restoredAuthority.authenticate(
          'Bearer ${tokens['synthetic-revoked-phone']}',
        ),
        throwsStateError,
      );
      expect(savedState(office), beforeSource);
      expect(await inventory(backup), beforeBackup);
    },
    skip: !Platform.isLinux,
  );

  test(
    'Normal startup rejects synthetic legacy and unrelated folders before changing files, settings, or permissions',
    () async {
      final legacy = await open('synthetic-legacy-workspace');
      await legacy.createWorkspace();
      await legacy.update({
        'notes': 'Synthetic legacy work that must be retained.',
      });
      legacy.setSetting('syntheticRetainedSetting', {
        'retain': true,
        'value': 17,
      });
      final legacyDevice = legacy.device;
      final legacyFields = await legacy.fields();
      await close(legacy);
      final legacyDirectory = path('synthetic-legacy-workspace');
      // Distinct permissions make an eager chmod observable even if all saved
      // record values happened to survive an unsafe startup attempt.
      expect(
        (await Process.run('chmod', ['755', legacyDirectory.path])).exitCode,
        0,
      );
      final legacyFiles = await inventory(legacyDirectory);
      final legacyMode = (await legacyDirectory.stat()).mode;

      final unrelated = path('synthetic-unrelated-folder');
      await unrelated.create();
      await File('${unrelated.path}/keep-this.txt').writeAsString(
        'Synthetic unrelated folder content. Preserve the exact bytes.',
        flush: true,
      );
      expect((await Process.run('chmod', ['755', unrelated.path])).exitCode, 0);
      final unrelatedFiles = await inventory(unrelated);
      final unrelatedMode = (await unrelated.stat()).mode;

      for (final directory in [legacyDirectory, unrelated]) {
        await expectLater(
          LabStore.open(directory, office: true, maintenanceOnly: true),
          throwsStateError,
        );
      }
      expect(await inventory(legacyDirectory), legacyFiles);
      expect((await legacyDirectory.stat()).mode, legacyMode);
      expect(await inventory(unrelated), unrelatedFiles);
      expect((await unrelated.stat()).mode, unrelatedMode);
      expect(
        await File('${unrelated.path}/workspace.sqlite').exists(),
        isFalse,
      );

      // The explicitly adopted fixture API can still read the retained legacy
      // records, proving that normal startup did not alter their identity/data.
      final retained = await open('synthetic-legacy-workspace');
      expect(retained.device, legacyDevice);
      expect(await retained.fields(), legacyFields);
      expect(retained.setting('syntheticRetainedSetting'), {
        'retain': true,
        'value': 17,
      });
      expect(retained.realWorkspace, isFalse);
      expect(retained.catalog, isNull);
    },
    skip: !Platform.isLinux,
  );

  test(
    'Fresh strict startup reopens the same maintenance office and rejects the phone role without writes',
    () async {
      final directory = path('synthetic-strict-office');
      expect(await directory.exists(), isFalse);
      var office = await open('synthetic-strict-office', maintenanceOnly: true);
      expect(
        office.setting('localMaintenanceApplication'),
        'org.vortice.next.maintenance_local',
      );
      expect(office.setting('localMaintenanceRole'), 'linux-office');
      expect(await owner(directory), {
        'application': 'org.vortice.next.maintenance_local',
        'role': 'linux-office',
        'version': 1,
      });
      await office.createCompany('Synthetic strict startup company');
      final job = await prepare(office, 'strict');
      final jobId = job['id'] as String;
      await office.update({
        'notes': 'Synthetic strict draft survives reopen.',
      }, jobId: jobId);
      final device = office.device;
      final catalog = canonical(office.catalog);
      final documentHash = digest(office.documentFor(jobId)!);
      await close(office);
      office = await open('synthetic-strict-office', maintenanceOnly: true);
      expect(office.device, device);
      expect(canonical(office.catalog), catalog);
      expect(digest(office.documentFor(jobId)!), documentHash);
      expect(
        valuesOf(await office.fields(jobId: jobId))['notes'],
        'Synthetic strict draft survives reopen.',
      );
      await close(office);
      final before = await inventory(directory);
      final beforeMode = (await directory.stat()).mode;

      await expectLater(
        LabStore.open(directory, office: false, maintenanceOnly: true),
        throwsStateError,
      );
      expect(await inventory(directory), before);
      expect((await directory.stat()).mode, beforeMode);
      final retained = await open(
        'synthetic-strict-office',
        maintenanceOnly: true,
      );
      expect(retained.device, device);
      expect(canonical(retained.catalog), catalog);
      expect(digest(retained.documentFor(jobId)!), documentHash);

      final emptyPhoneFolder = path('synthetic-empty-phone-folder');
      await emptyPhoneFolder.create();
      final phone = await LabStore.open(
        emptyPhoneFolder,
        office: false,
        maintenanceOnly: true,
      );
      stores.add(phone);
      expect(await owner(emptyPhoneFolder), {
        'application': 'org.vortice.next.maintenance_local',
        'role': 'mechanic-phone',
        'version': 1,
      });
      expect(phone.setting('localMaintenanceRole'), 'mechanic-phone');
      await close(phone);
      final beforeWrongOffice = await inventory(emptyPhoneFolder);
      await expectLater(
        LabStore.open(emptyPhoneFolder, office: true, maintenanceOnly: true),
        throwsStateError,
      );
      expect(await inventory(emptyPhoneFolder), beforeWrongOffice);
    },
    skip: !Platform.isLinux,
  );
}
