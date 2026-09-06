import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/checklists/saved_checklist_history_writer.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';

class _NoLegacyHistory implements SavedChecklistHistoryWriter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Legacy write attempted');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production operator submission survives restart with ordered photo and immutable run',
    () async {
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp('next-operator-');
      final file = File('${directory.path}/account.sqlite');
      var database = AppDatabase.forAccount(
        'operator-a',
        executor: NativeDatabase(file),
      );
      var queue = FieldWorkQueue(
        database,
        account: 'operator-a',
        currentAccount: () => 'operator-a',
        send: (_) async => throw const SocketException('Offline'),
      );
      final container = ProviderContainer(
        overrides: [
          fieldWorkQueueProvider.overrideWithValue(queue),
          savedChecklistHistoryWriterProvider.overrideWithValue(
            _NoLegacyHistory(),
          ),
        ],
      );
      final photo = Uint8List.fromList([137, 80, 78, 71, 13, 10]);
      try {
        await container
            .read(operationsChecklistSubmissionProvider)
            .submit(
              assetId: 'asset-a',
              assetClientId: 'client-a',
              operatorId: 'operator-a',
              submittedByRole: 'operator',
              runType: 'pre_departure',
              operationId: 'run-a',
              template: const ChecklistTemplate(
                id: 'template-a',
                name: 'Daily',
                checklistType: 'operator_daily',
              ),
              items: [
                const ChecklistItem(
                  id: 'item-a',
                  templateId: 'template-a',
                  descriptionEn: 'Oil',
                  requiresPhoto: true,
                ),
              ],
              responses: {'item-a': 'monitor'},
              notes: {'item-a': 'Watch oil level'},
              submittedAt: DateTime.utc(2026, 9, 6),
              currentHours: 42,
              generalNotes: 'Restart proof',
              photos: {'item-a': photo},
            );
        expect((await queue.list()).map((o) => o.status), [
          'pending',
          'pending',
        ]);
        container.dispose();
        queue.close();
        await database.close();
        final sent = <FieldOperation>[];
        database = AppDatabase.forAccount(
          'operator-a',
          executor: NativeDatabase(file),
        );
        queue = FieldWorkQueue(
          database,
          account: 'operator-a',
          currentAccount: () => 'operator-a',
          send: (operation) async => sent.add(operation),
        );
        await queue.flush();
        expect(sent.map((o) => o.kind), [
          'upload',
          'submit_operations_checklist',
        ]);
        expect(base64Decode(sent.first.payload['bytes'] as String), photo);
        final payload = sent.last.payload['p_data'] as Map;
        expect(payload['photos'], {
          'item-a': 'asset-a/operator-a/run-a/item-a.png',
        });
        expect(payload['responses'], {'item-a': 'monitor'});
        await queue.flush();
        expect(
          sent,
          hasLength(2),
          reason: 'Acknowledged work must not submit again',
        );
      } finally {
        queue.close();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
