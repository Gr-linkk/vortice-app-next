import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/model.dart';

import 'inspection_editor_coherence_support.dart';

void main() {
  setUpAll(initializeEditorNative);

  test(
    'stale queued hash rejects before submission writes and exact retry replays',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final seen = digest(fixture.store.documentFor(fixture.job)!);
      final release = Completer<void>();
      final gate = fixture.store.queue.run(() => release.future);
      final incoming = fixture.store.update({
        'notes': 'Incoming queued finding.',
      }, jobId: fixture.job);
      final submission = fixture.store.submit(
        jobId: fixture.job,
        expectedDocumentHash: seen,
      );
      final rejection = expectLater(
        submission,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            changedInspectionMessage,
          ),
        ),
      );
      release.complete();
      await gate;
      await incoming;
      await rejection;
      expect(fixture.store.submissions, isEmpty);
      expect(
        fixture.store.db.select("SELECT * FROM events WHERE kind='submitted'"),
        isEmpty,
      );
      final current = digest(fixture.store.documentFor(fixture.job)!);
      final first = await fixture.store.submit(
        jobId: fixture.job,
        expectedDocumentHash: current,
      );
      final replay = await fixture.store.submit(
        jobId: fixture.job,
        expectedDocumentHash: current,
      );
      expect(canonical(replay), canonical(first));
      expect(fixture.store.submissions, hasLength(1));
      final decoded = await decodeEditorFields(
        base64Decode(first['document'] as String),
      );
      expect(first['values'], valuesOf(decoded));
      expect(first['documentHash'], current);
    },
  );

  test(
    'different bytes with equal visible values still require a reviewed hash',
    () async {
      final fixture = await EditorFixture.create();
      addTearDown(fixture.close);
      final firstBytes = fixture.store.documentFor(fixture.job)!;
      final original = valuesOf(await fixture.store.fields(jobId: fixture.job));
      await fixture.store.update({
        'notes': 'Changed then reverted.',
      }, jobId: fixture.job);
      await fixture.store.update({
        'notes': original['notes'],
      }, jobId: fixture.job);
      final current = fixture.store.documentFor(fixture.job)!;
      expect(
        valuesOf(await fixture.store.fields(jobId: fixture.job)),
        original,
      );
      expect(digest(current), isNot(digest(firstBytes)));
      await expectLater(
        fixture.store.submit(
          jobId: fixture.job,
          expectedDocumentHash: digest(firstBytes),
        ),
        throwsStateError,
      );
      expect(fixture.store.submissions, isEmpty);
      final submitted = await fixture.store.submit(
        jobId: fixture.job,
        expectedDocumentHash: digest(current),
      );
      expect(submitted['documentHash'], digest(current));
    },
  );
}
