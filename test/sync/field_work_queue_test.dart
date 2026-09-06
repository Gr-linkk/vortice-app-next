import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/core/account_storage.dart';

void main() {
  test(
    'correcting an archived report restores its photo without replaying rejected work',
    () async {
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      final sent = <String>[];
      final queue = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: (o) async => sent.add(o.id),
      );
      try {
        await queue.enqueue(
          const FieldOperation(
            id: 'photo:job/a/p.png',
            kind: 'upload',
            subject: 'job',
            payload: {'path': 'job/a/p.png'},
          ),
        );
        await queue.enqueue(
          const FieldOperation(
            id: 'old-report',
            kind: 'rpc',
            subject: 'job',
            payload: {},
          ),
        );
        await queue.archiveSubject('job');
        await queue.restoreEvidence(['job/a/p.png']);
        await queue.enqueue(
          const FieldOperation(
            id: 'corrected-report',
            kind: 'rpc',
            subject: 'job',
            payload: {},
          ),
        );
        await queue.flush();
        expect(sent, ['photo:job/a/p.png', 'corrected-report']);
        expect(
          (await queue.list()).singleWhere((o) => o.id == 'old-report').status,
          'cancelled',
        );
      } finally {
        await db.close();
      }
    },
  );
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'restart and lost acknowledgement retain exactly one immutable submission',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'vortice-next-queue-',
      );
      final file = File('${folder.path}/account-a.sqlite');
      var db = AppDatabase.forAccount('a', executor: NativeDatabase(file));
      final delivered = <String>{};
      var loseResponse = true;
      Future<void> send(FieldOperation op) async {
        delivered.add(op.id);
        if (loseResponse) throw TimeoutException('acknowledgement lost');
      }

      final first = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: send,
      );
      const op = FieldOperation(
        id: 'operation-1',
        kind: 'rpc',
        subject: 'job',
        payload: {'hours': 2},
      );
      await first.submit(op);
      expect((await first.list()).single.status, 'pending');
      first.close();
      await db.close();
      db = AppDatabase.forAccount('a', executor: NativeDatabase(file));
      final restarted = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: send,
      );
      loseResponse = false;
      await restarted.submit(op);
      expect(delivered, {'operation-1'});
      expect((await restarted.list()).single.status, 'synced');
      await expectLater(
        restarted.enqueue(
          const FieldOperation(
            id: 'operation-1',
            kind: 'rpc',
            subject: 'job',
            payload: {'hours': 4},
          ),
        ),
        throwsStateError,
      );
      await db.close();
      await folder.delete(recursive: true);
    },
  );
  test(
    'account switching never sends retained operations and server conflict blocks dependent work',
    () async {
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      String? active = 'a';
      final sent = <String>[];
      final queue = FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => active,
        send: (op) async {
          sent.add(op.id);
          if (op.id == 'conflict') {
            throw const PostgrestException(message: 'Changed', code: '40001');
          }
        },
      );
      for (final op in [
        const FieldOperation(
          id: 'conflict',
          kind: 'rpc',
          subject: 'job-a',
          payload: {},
        ),
        const FieldOperation(
          id: 'dependent',
          kind: 'rpc',
          subject: 'job-a',
          payload: {},
        ),
        const FieldOperation(
          id: 'independent',
          kind: 'rpc',
          subject: 'job-b',
          payload: {},
        ),
      ]) {
        await queue.enqueue(op);
      }
      active = 'b';
      await expectLater(queue.flush(), throwsA(isA<AccountChangedException>()));
      expect(sent, isEmpty);
      active = 'a';
      await queue.flush();
      expect(sent, ['conflict', 'independent']);
      final rows = await queue.list();
      expect(rows.first.status, 'failed');
      expect(rows[1].status, 'pending');
      expect(rows.last.status, 'synced');
      await db.close();
    },
  );
}
