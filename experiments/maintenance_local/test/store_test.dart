import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/evidence_store.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  setUpAll(
    () async => RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    ),
  );
  late Directory root;
  final stores = <LabStore>[];
  Future<LabStore> open(
    String name,
    bool office, {
    DateTime Function()? clock,
  }) async {
    final s = await LabStore.open(
      Directory('${root.path}/$name'),
      office: office,
      now: clock,
    );
    stores.add(s);
    return s;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vortice-store-test-');
  });
  tearDown(() async {
    for (final s in stores) {
      await s.close();
    }
    stores.clear();
    await root.delete(recursive: true);
  });

  Future<void> fill(LabStore s) async {
    await s.update({
      'fluid': 'pass',
      'guards': 'attention',
      'meter': 125.5,
      'notes': 'Inspect the loose guard before use.',
    });
    await s.attach([1, 2, 3, 4, 5]);
  }

  test(
    'Offline submission survives reopen and 30 days; no invented zero meter',
    () async {
      var s = await open('office', true);
      await s.createWorkspace();
      expect(valuesOf(await s.fields())['meter'], isNull);
      await fill(s);
      final submitted = await s.submit();
      final photo = (submitted['values'] as Json)['photo'] as String;
      await s.close();
      stores.remove(s);
      s = await open(
        'office',
        true,
        clock: () => DateTime.now().add(const Duration(days: 30)),
      );
      expect(s.submissions.single['id'], submitted['id']);
      expect(await s.evidence.complete(photo), isTrue);
      expect(valuesOf(await s.fields())['meter'], 125.5);
    },
  );

  test('Submission retries are exact and decisions remain immutable', () async {
    final office = await open('office', true);
    await office.createWorkspace();
    await fill(office);
    final p = await office.submit();
    await office.acceptSubmission(p, office.device);
    expect(office.submissions.length, 1);
    await expectLater(
      office.acceptSubmission({...p, 'createdAt': 'changed'}, office.device),
      throwsStateError,
    );
    final r = await office.decide(p['id'] as String, approve: true);
    expect(await office.decide(p['id'] as String, approve: true), r);
    await office.update({
      'notes': 'Later edits must not replace the reviewed version.',
    });
    expect(
      (office.receipts.single['values'] as Json)['notes'],
      'Inspect the loose guard before use.',
    );
    await expectLater(
      office.decide(p['id'] as String, approve: false, reason: 'change'),
      throwsStateError,
    );
  });

  test(
    'A conflict choice from an older editor preserves a later saved edit',
    () async {
      final office = await open('office', true);
      await office.createWorkspace();
      final phone = await open('phone', false);
      await phone.importOfficeBundle(await office.publicBundle());
      await office.update({'notes': 'Office note.'});
      await phone.update({'notes': 'Phone note.'});
      await phone.importOfficeBundle(await office.publicBundle());
      final editor = phone.document!;
      expect(conflicts(await phone.fields()), contains('notes'));
      await phone.update({'notes': 'Newer unseen note.'});
      await phone.update({'notes': 'Phone note.'}, base: editor);
      expect((await phone.fields())['notes'], [
        'Newer unseen note.',
        'Phone note.',
      ]);
    },
  );

  test(
    'Missing photo and conflicting draft block approval; phone has no approval authority',
    () async {
      final office = await open('office', true);
      await office.createWorkspace();
      final phone = await open('phone', false);
      await phone.importOfficeBundle(await office.publicBundle());
      await fill(phone);
      final p = await phone.submit();
      await office.acceptSubmission(p, phone.device);
      await expectLater(
        office.decide(p['id'] as String, approve: true),
        throwsStateError,
      );
      await expectLater(
        phone.decide(p['id'] as String, approve: true),
        throwsStateError,
      );
      await expectLater(
        office.acceptSubmission(p, 'another-device'),
        throwsStateError,
      );
      await office.update({'meter': 111});
      await phone.importOfficeBundle(await office.publicBundle());
      expect(conflicts(await phone.fields()), contains('meter'));
      await expectLater(phone.submit(), throwsStateError);
      await phone.update({'meter': 125.5});
      expect(conflicts(await phone.fields()), isEmpty);
    },
  );

  test(
    'Chunk transfer resumes and corrupt content cannot become complete evidence',
    () async {
      final s = EvidenceStore(Directory('${root.path}/evidence'));
      final bytes = List.generate(600000, (i) => i % 251),
          hash = digest(List.generate(600000, (i) => i % 251));
      await s.append(
        hash,
        0,
        bytes.length,
        bytes.sublist(0, EvidenceStore.chunkBytes),
      );
      expect((await s.status(hash))['offset'], EvidenceStore.chunkBytes);
      expect(await s.complete(hash), isFalse);
      final reopened = EvidenceStore(s.root);
      await reopened.append(
        hash,
        EvidenceStore.chunkBytes,
        bytes.length,
        bytes.sublist(EvidenceStore.chunkBytes, 2 * EvidenceStore.chunkBytes),
      );
      await reopened.append(
        hash,
        2 * EvidenceStore.chunkBytes,
        bytes.length,
        bytes.sublist(2 * EvidenceStore.chunkBytes),
      );
      expect(await reopened.complete(hash), isTrue);
      await expectLater(
        reopened.append(hash, 0, bytes.length, [9, 9, 9]),
        throwsStateError,
      );
      final bad = digest([7, 7, 7]);
      await expectLater(
        reopened.append(bad, 0, 3, [8, 8, 8]),
        throwsStateError,
      );
      expect(await reopened.complete(bad), isFalse);
      final late = digest([4, 5, 6]);
      await File(
        '${reopened.file(late).path}.part',
      ).writeAsBytes([4, 5, 6], flush: true);
      expect((await reopened.status(late))['complete'], isTrue);
    },
  );

  test(
    'Local photo save resumes a crash inside the first or a later chunk',
    () async {
      final bytes = List.generate(600000, (i) => i % 251),
          hash = digest(List.generate(600000, (i) => i % 251));
      for (final length in [
        1,
        777,
        EvidenceStore.chunkBytes - 1,
        EvidenceStore.chunkBytes,
        EvidenceStore.chunkBytes + 777,
        599999,
        600000,
      ]) {
        final s = EvidenceStore(Directory('${root.path}/partial-$length'));
        await s.root.create(recursive: true);
        await File(
          '${s.file(hash).path}.part',
        ).writeAsBytes(bytes.sublist(0, length), flush: true);
        expect(await s.add(bytes), hash);
        expect(await s.complete(hash), isTrue);
      }
      final s = EvidenceStore(Directory('${root.path}/changed-prefix'));
      await s.root.create(recursive: true);
      await File(
        '${s.file(hash).path}.part',
      ).writeAsBytes([9, 9, 9], flush: true);
      await expectLater(s.add(bytes), throwsStateError);
    },
  );
}
