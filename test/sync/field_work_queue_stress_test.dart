import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/sync/field_work_queue.dart';

void main() {
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    '300 queued operations with 25 concurrent flush callers send once in order',
    () async {
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      addTearDown(db.close);
      final sent = <String>[];
      final queue = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: (op) async {
          await Future<void>.delayed(Duration.zero);
          sent.add(op.id);
        },
      );
      for (var i = 0; i < 300; i++) {
        await queue.enqueue(
          FieldOperation(
            id: 'op-$i',
            kind: 'rpc',
            subject: 'job-${i % 20}',
            payload: {'i': i},
          ),
        );
      }
      await Future.wait(List.generate(25, (_) => queue.flush()));
      expect(sent, List.generate(300, (i) => 'op-$i'));
      expect(
        (await queue.list()).every((op) => op.synced && op.attempts == 1),
        isTrue,
      );
      await queue.flush();
      expect(sent.length, 300);
    },
  );

  test(
    '200 operations keep rejected subject isolated while 19 other subjects complete',
    () async {
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      addTearDown(db.close);
      final sent = <String>[];
      var reject = true;
      final queue = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: (op) async {
          sent.add(op.id);
          if (reject && op.subject == 'job-0') {
            throw const PostgrestException(
              message: 'Rejected fixture',
              code: '42501',
            );
          }
        },
      );
      for (var i = 0; i < 200; i++) {
        await queue.enqueue(
          FieldOperation(
            id: 'op-$i',
            kind: 'rpc',
            subject: 'job-${i % 20}',
            payload: {'i': i},
          ),
        );
      }
      await Future.wait(List.generate(10, (_) => queue.flush()));
      final rows = await queue.list();
      expect(rows.where((op) => op.synced).length, 190);
      expect(rows.where((op) => op.status == 'failed').length, 1);
      expect(rows.where((op) => op.status == 'pending').length, 9);
      expect(sent.length, 191);
      await queue.flush();
      expect(sent.length, 191);
      reject = false;
      await queue.flush(retryFailed: true);
      expect((await queue.list()).every((op) => op.synced), isTrue);
      expect(sent.length, 201);
    },
  );

  test(
    'account switch during first send retains all 200 unacknowledged operations',
    () async {
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      addTearDown(db.close);
      var active = 'a';
      final sent = <String>[];
      final entered = Completer<void>();
      final release = Completer<void>();
      final queue = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => active,
        send: (op) async {
          sent.add(op.id);
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        },
      );
      for (var i = 0; i < 200; i++) {
        await queue.enqueue(
          FieldOperation(
            id: 'op-$i',
            kind: 'rpc',
            subject: 'job-$i',
            payload: {'i': i},
          ),
        );
      }
      final flushing = queue.flush();
      final failed = expectLater(
        flushing,
        throwsA(isA<AccountChangedException>()),
      );
      await entered.future;
      active = 'b';
      release.complete();
      await failed;
      expect(sent, ['op-0']);
      active = 'a';
      expect(
        (await queue.list()).every((op) => op.status == 'pending'),
        isTrue,
      );
      await queue.flush();
      expect((await queue.list()).every((op) => op.synced), isTrue);
      expect(sent, ['op-0', ...List.generate(200, (i) => 'op-$i')]);
    },
  );
}
