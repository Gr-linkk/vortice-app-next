import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/sync/field_evidence.dart';
import 'package:vortice_app/sync/field_work_queue.dart';

void main() {
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'provider photo survives SQLite reopen, previews offline and retries identical bytes',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'next-provider-evidence-',
      );
      final file = File('${directory.path}/account.db');
      var account = 'actor';
      var online = false;
      var loseAck = true;
      final accepted = <String, Object>{};
      final attempts = <Map<String, dynamic>>[];
      Future<void> send(FieldOperation row) async {
        attempts.add(row.payload);
        if (!online) throw const SocketException('Offline');
        accepted.putIfAbsent(row.id, () => row.payload['bytes']);
        expect(accepted[row.id], row.payload['bytes']);
        if (loseAck) {
          loseAck = false;
          throw TimeoutException('Uploaded, acknowledgement lost');
        }
      }

      var db = AppDatabase.forAccount('actor', executor: NativeDatabase(file));
      var queue = FieldWorkQueue(
        db,
        account: 'actor',
        currentAccount: () => account,
        send: send,
      );
      const path = 'work/actor/pressure.jpg';
      final bytes = Uint8List.fromList([11, 22, 33, 44]);
      try {
        await queue.enqueue(fieldEvidenceOperation(path: path, bytes: bytes));
        await queue.flush();
        expect((await queue.list()).single.status, 'pending');
        queue.close();
        await db.close();
        db = AppDatabase.forAccount('actor', executor: NativeDatabase(file));
        queue = FieldWorkQueue(
          db,
          account: 'actor',
          currentAccount: () => account,
          send: send,
        );
        expect(await localFieldEvidence(queue, path), bytes);
        await expectLater(
          requireUploadedFieldEvidence(queue, [path]),
          throwsStateError,
        );
        online = true;
        await expectLater(
          requireUploadedFieldEvidence(queue, [path]),
          throwsStateError,
        );
        await requireUploadedFieldEvidence(queue, [path]);
        expect(accepted.length, 1);
        expect((await queue.list()).single.status, 'synced');
        expect(
          attempts.every(
            (payload) => payload.toString() == attempts.first.toString(),
          ),
          isTrue,
        );
        account = 'other';
        await expectLater(
          localFieldEvidence(queue, path),
          throwsA(isA<AccountChangedException>()),
        );
        await expectLater(
          requireUploadedFieldEvidence(queue, [path]),
          throwsA(isA<AccountChangedException>()),
        );
      } finally {
        queue.close();
        await db.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'rejected provider photo remains recoverable and cannot permit submission',
    () async {
      final db = AppDatabase.forAccount(
        'actor',
        executor: NativeDatabase.memory(),
      );
      final queue = FieldWorkQueue(
        db,
        account: 'actor',
        currentAccount: () => 'actor',
        send: (_) async {
          throw const PostgrestException(
            message: 'Assignment revoked',
            code: '42501',
          );
        },
      );
      try {
        const path = 'work/actor/rejected.jpg';
        final bytes = Uint8List.fromList([4, 5, 6]);
        await queue.enqueue(fieldEvidenceOperation(path: path, bytes: bytes));
        await expectLater(
          requireUploadedFieldEvidence(queue, [path]),
          throwsStateError,
        );
        expect((await queue.list()).single.needsAttention, isTrue);
        expect(await localFieldEvidence(queue, path), bytes);
        expect(
          await queue.cleanCompleted(
            now: DateTime.now().add(const Duration(days: 90)),
          ),
          0,
        );
        await expectLater(
          queue.enqueue(
            fieldEvidenceOperation(path: path, bytes: Uint8List.fromList([7])),
          ),
          throwsStateError,
        );
      } finally {
        queue.close();
        await db.close();
      }
    },
  );
}
