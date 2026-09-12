import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/operator/operator_checklist_draft_store.dart';
import 'package:vortice_app/features/operator/operator_checklist_support.dart';

Map<String, dynamic> draft(String operation, String asset) => {
  'operation_id': operation,
  'assetId': asset,
  'templateId': 'published-v1',
  'responses': {'oil': 'monitor'},
  'notes': {'oil': 'Watch it'},
  'photos': {'oil': 'AQIDBA=='},
  'started_at': '2026-09-12T00:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'new runs and removing one run preserve other draft photos and replay identity',
    () async {
      final store = OperatorChecklistDraftStore('a', () => 'a');
      await store.save(draft('first', 'dredge'));
      await store.save(draft('second', 'truck'));
      await store.remove('second');
      expect(await store.list(), [draft('first', 'dredge')]);
    },
  );
  test(
    'imports generic and pinned legacy drafts repeatedly including outbox corrections',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final key = accountStorageKey('a', operatorChecklistDraftKey);
      await prefs.setString(key, jsonEncode(draft('first', 'dredge')));
      await prefs.setString(
        '$key:assignment',
        jsonEncode(draft('assigned', 'truck')),
      );
      final store = OperatorChecklistDraftStore('a', () => 'a');
      expect((await store.list()).length, 2);
      expect(prefs.getString(key), isNull);
      expect((await store.list()).length, 2);
      await prefs.setString(
        key,
        jsonEncode({...draft('correction', 'dredge')}..remove('operation_id')),
      );
      final loaded = await store.list();
      expect(loaded.length, 3);
      expect(
        loaded.singleWhere(
          (d) => d['operation_id'] == 'assigned',
        )['assignment_id'],
        'assignment',
      );
      expect(
        loaded.every((d) => (d['photos'] as Map)['oil'] == 'AQIDBA=='),
        isTrue,
      );
      expect((await store.list()).length, 3);
    },
  );
  test(
    'account switch neither exposes nor mutates the prior account drafts',
    () async {
      String current = 'a';
      final oldStore = OperatorChecklistDraftStore('a', () => current);
      await oldStore.save(draft('first', 'dredge'));
      current = 'b';
      expect(oldStore.list(), throwsA(isA<AccountChangedException>()));
      expect(
        oldStore.save(draft('second', 'truck')),
        throwsA(isA<AccountChangedException>()),
      );
      expect(
        await OperatorChecklistDraftStore('b', () => current).list(),
        isEmpty,
      );
      current = 'a';
      expect((await oldStore.list()).single['operation_id'], 'first');
    },
  );
  test(
    'unreadable legacy data remains intact while other saved runs load',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final key = accountStorageKey('a', operatorChecklistDraftKey);
      await prefs.setString(key, '{broken');
      final store = OperatorChecklistDraftStore('a', () => 'a');
      await store.save(draft('good', 'truck'));
      expect((await store.list()).single['operation_id'], 'good');
      expect(prefs.getString(key), '{broken');
    },
  );
}
