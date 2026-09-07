import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/sync/evidence_submission.dart';
import 'package:vortice_app/sync/field_work_queue.dart';

void main() {
  test(
    'lost finish acknowledgement retries original text, photos and signature',
    () async {
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
      final objects = <String, List<int>>{};
      final begins = <Map<String, dynamic>>[];
      var finishes = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('begin_report_submission')) {
          begins.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }
        if (r.url.path.endsWith('finish_evidence_submission')) {
          finishes++;
          if (finishes == 1) throw TimeoutException('Acknowledgement lost');
          return http.Response('{}', 200);
        }
        final path = r.url.path.replaceFirst('/authenticated', '');
        if (r.method == 'GET') return http.Response.bytes(objects[path]!, 200);
        if (objects.containsKey(path)) return http.Response('{}', 409);
        objects[path] = r.bodyBytes;
        return http.Response('{}', 200);
      });
      FieldWorkQueue queue() => FieldWorkQueue(
        db,
        account: 'a',
        currentAccount: () => 'a',
        send: (o) => EvidenceSubmissionTransport(
          client: client,
          headers: const {},
          checkAccount: () {},
          baseUrl: 'https://example.test',
        ).send(o),
      );
      try {
        final first = queue();
        final op = await prepareEvidenceSubmission(
          queue: first,
          kind: 'report',
          record: 'original',
          data: {'work_order_id': 'job', 'complaint': 'preserved'},
          photos: [
            Uint8List.fromList([1, 2, 3]),
          ],
          signature: Uint8List.fromList([4, 5]),
        );
        await first.submit(op);
        expect((await first.list()).single.status, 'pending');
        first.close();
        final restarted = queue();
        await restarted.flush();
        expect((await restarted.list()).single.synced, true);
        expect(objects.length, 2);
        expect(begins.length, 2);
        expect(begins.first, begins.last);
        expect(
          begins.singleWhere((e) => identical(e, begins.first))['p_report'],
          'original',
        );
        expect(
          await restarted.cleanCompleted(
            now: DateTime.now().add(const Duration(days: 8)),
          ),
          1,
        );
        expect(await restarted.list(), isEmpty);
      } finally {
        client.close();
        await db.close();
      }
    },
  );
  test('storage rejection cannot acknowledge or discard evidence', () async {
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    final db = AppDatabase.forAccount('a', executor: NativeDatabase.memory());
    var finish = false;
    final client = MockClient((r) async {
      if (r.url.path.contains('begin_request')) return http.Response('{}', 200);
      if (r.url.path.contains('finish_')) finish = true;
      return http.Response('{"message":"Denied","code":"42501"}', 403);
    });
    final queue = FieldWorkQueue(
      db,
      account: 'a',
      currentAccount: () => 'a',
      send: (o) => EvidenceSubmissionTransport(
        client: client,
        headers: const {},
        checkAccount: () {},
        baseUrl: 'https://example.test',
      ).send(o),
    );
    try {
      final op = await prepareEvidenceSubmission(
        queue: queue,
        kind: 'request',
        record: 'original',
        data: {'description': 'retained'},
        photos: [
          Uint8List.fromList([1, 2]),
        ],
      );
      await queue.submit(op);
      expect(finish, false);
      expect((await queue.list()).single.status, 'failed');
      expect(
        await queue.cleanCompleted(
          now: DateTime.now().add(const Duration(days: 30)),
        ),
        0,
      );
      expect((await queue.list()).single.payload, op.payload);
    } finally {
      client.close();
      await db.close();
    }
  });
}
