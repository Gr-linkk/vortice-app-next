import 'dart:ffi';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/work_orders/work_order_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unattributed cache never supplies work when signed out and offline',
    () async {
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.invalid',
        anonKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
        httpClient: MockClient(
          (_) async => throw http.ClientException('Offline'),
        ),
      );
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.workOrdersDao.upsert(
          const WorkOrdersTableCompanion(
            id: Value('private-a'),
            assetId: Value('asset-a'),
            clientId: Value('company-a'),
            createdBy: Value('owner-a'),
            title: Value('Private A'),
          ),
        );
        final repo = WorkOrderRepository(db);
        await expectLater(
          repo.getWorkOrderById('private-a'),
          throwsA(isA<http.ClientException>()),
        );
        await expectLater(
          repo.listWorkOrders(),
          throwsA(isA<http.ClientException>()),
        );
        expect(
          await db.workOrdersDao.getById('private-a'),
          isNotNull,
          reason: 'Keep legacy data without exposing or deleting it',
        );
      } finally {
        await db.close();
        await Supabase.instance.dispose();
      }
    },
  );
}
