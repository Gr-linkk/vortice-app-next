import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/service_reports/service_report_repository.dart';

void main() {
  if (Platform.isLinux) {
    // Linux runtime installations may omit the development-only .so symlink.
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'asset refresh preserves pending report even without a cached work order',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/service_reports')) {
            throw http.ClientException('Offline write');
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'pending',
                'work_order_id': 'uncached-work',
                'complaint': 'Old remote content',
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(db.close);
      addTearDown(client.dispose);
      final repository = ServiceReportRepository(db, client: client);
      await repository.createLocalFirst(
        reportId: 'pending',
        workOrderId: 'uncached-work',
        complaint: 'Retain this edit',
      );
      expect(
        (await repository.listForAsset('asset')).single.complaint,
        'Retain this edit',
      );
      expect(
        (await db.serviceReportsDao.listPendingSync()).single.complaint,
        'Retain this edit',
      );
    },
  );

  test(
    'direct report read loads and caches a remote report on a fresh device',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                'id': 'report-1',
                'work_order_id': 'work-1',
                'complaint': 'Remote report',
                'created_at': '2026-09-06T05:55:00Z',
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(db.close);
      addTearDown(client.dispose);
      final report = await ServiceReportRepository(
        db,
        client: client,
      ).getById('report-1');
      expect(report?.complaint, 'Remote report');
      expect(
        (await db.serviceReportsDao.getById('report-1'))?.complaint,
        'Remote report',
      );
    },
  );

  test('report upload includes UTC offsets on all timestamps', () async {
    final db = AppDatabase(NativeDatabase.memory());
    Map<String, dynamic>? payload;
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 201, request: request);
      }),
    );
    addTearDown(db.close);
    addTearDown(client.dispose);
    final result = await ServiceReportRepository(db, client: client)
        .createLocalFirst(
          workOrderId: 'work-1',
          complaint: 'Audit',
          cause: 'Test',
          correction: 'Done',
          techSignatureUrl: 'synthetic-signature',
        );
    expect(result.synced, isTrue);
    for (final key in ['created_at', 'updated_at', 'signed_at']) {
      expect(payload![key], endsWith('Z'), reason: key);
    }
  });

  test('client switching accounts cannot read another cached report', () async {
    final db = AppDatabase(NativeDatabase.memory());
    var visible = true;
    var offline = false;
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        if (offline) throw http.ClientException('Offline');
        return http.Response(
          jsonEncode(
            visible
                ? [
                    {
                      'id': 'private-report',
                      'work_order_id': 'private-work',
                      'complaint': 'Company A only',
                    },
                  ]
                : [],
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(db.close);
    addTearDown(client.dispose);
    await ServiceReportRepository(db, client: client).getById('private-report');
    visible = false;
    final otherClient = ServiceReportRepository(
      db,
      client: client,
      canAuthor: false,
    );
    expect(await otherClient.getById('private-report'), isNull);
    expect(await otherClient.listAll(), isEmpty);
    offline = true;
    await expectLater(
      otherClient.getById('private-report'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test(
    'client reads neither upload nor discard a provider pending report',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      var rejectUpload = true;
      var writes = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/service_reports')) {
            writes++;
            if (rejectUpload) throw http.ClientException('Offline');
          }
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(db.close);
      addTearDown(client.dispose);
      final submitted = await ServiceReportRepository(
        db,
        client: client,
      ).createLocalFirst(workOrderId: 'work', complaint: 'Provider draft');
      expect(submitted.synced, isFalse);
      final before = writes;
      rejectUpload = false;
      final reader = ServiceReportRepository(
        db,
        client: client,
        canAuthor: false,
      );
      expect(await reader.listAll(), isEmpty);
      expect(await reader.getById(submitted.reportId), isNull);
      expect(writes, before);
      expect((await db.serviceReportsDao.listPendingSync()).length, 1);
    },
  );
}
