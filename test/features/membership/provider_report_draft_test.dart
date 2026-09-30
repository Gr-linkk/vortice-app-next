import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/membership/provider_report_draft.dart';

class FailingDisk extends InMemorySharedPreferencesStore {
  FailingDisk() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      fail ? false : super.setValue(valueType, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'failed disk write sends nothing and a later save can recover',
    () async {
      final disk = FailingDisk();
      SharedPreferencesStorePlatform.instance = disk;
      var sent = 0;
      final draft = ProviderReportDraft(
        account: 'a',
        organizationId: 'org',
        workOrderId: 'job',
        currentAccount: () => 'a',
        send: (_) async {
          sent++;
        },
      );
      await draft.load();
      await expectLater(
        draft.submit(
          revision: 1,
          action: 'save_report',
          data: {'notes': 'captured'},
        ),
        throwsStateError,
      );
      expect(sent, 0);
      disk.fail = false;
      await draft.submit(
        revision: 1,
        action: 'save_report',
        data: {'notes': 'captured'},
      );
      expect(sent, 1);
      expect(
        (await SharedPreferences.getInstance()).getString(draft.storageKey),
        isNull,
      );
    },
  );

  test(
    'malformed saved command is retained and cannot be overwritten',
    () async {
      final draft = ProviderReportDraft(
        account: 'a',
        organizationId: 'org',
        workOrderId: 'job',
        currentAccount: () => 'a',
        send: (_) async => fail('must not send'),
      );
      final prefs = await SharedPreferences.getInstance();
      const corrupt = '{"data":{},"pending":{"id":"original"}}';
      await prefs.setString(draft.storageKey, corrupt);
      await expectLater(draft.load(), throwsA(anything));
      await draft.save({'notes': 'older server copy'});
      await expectLater(
        draft.submit(revision: 1, action: 'submit', data: {}),
        throwsStateError,
      );
      expect(prefs.getString(draft.storageKey), corrupt);
    },
  );

  test('account change during send keeps the original account retry', () async {
    var account = 'a';
    final response = Completer<void>();
    final started = Completer<void>();
    final draft = ProviderReportDraft(
      account: 'a',
      organizationId: 'org',
      workOrderId: 'job',
      currentAccount: () => account,
      send: (_) {
        started.complete();
        return response.future;
      },
    );
    await draft.load();
    final save = draft.submit(
      revision: 3,
      action: 'submit',
      data: {'notes': 'saved'},
    );
    final rejected = expectLater(save, throwsA(isA<AccountChangedException>()));
    await started.future;
    account = 'b';
    response.complete();
    await rejected;
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(draft.storageKey)!)['pending']['revision'],
      3,
    );
    expect(
      prefs.getString(accountStorageKey('b', 'provider_report:org:job')),
      isNull,
    );
  });
}
