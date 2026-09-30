import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/retryable_rpc.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final code in ['504', '08007', '40003', 'PGRST003', 'unrecognized']) {
    test(
      'uncertain $code preserves the exact command across client restart',
      () async {
        final sent = <Map<String, dynamic>>[];
        var fail = true;
        RetryableRpc client() => RetryableRpc(
          account: 'user-a',
          currentAccount: () => 'user-a',
          send: (_, params) async {
            sent.add(params);
            if (fail) {
              throw PostgrestException(message: 'Uncertain', code: code);
            }
            return null;
          },
        );
        await expectLater(
          client().call('save', {'value': 3}, captureTime: true),
          throwsA(isA<PostgrestException>()),
        );
        expect((await SharedPreferences.getInstance()).getKeys(), hasLength(1));
        fail = false;
        await client().call('save', {'value': 3}, captureTime: true);
        expect(sent[1], sent[0]);
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      },
    );
  }

  for (final code in ['P0001', '40001', '42501', '23505', '22P02', '40P01']) {
    test('confirmed $code allows a fresh operation after rejection', () async {
      final sent = <Map<String, dynamic>>[];
      final client = RetryableRpc(
        account: 'user-a',
        currentAccount: () => 'user-a',
        send: (_, params) async {
          sent.add(params);
          if (sent.length == 1) {
            throw PostgrestException(message: 'Rejected', code: code);
          }
          return null;
        },
      );
      await expectLater(
        client.call('save', {'value': 3}),
        throwsA(isA<PostgrestException>()),
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await client.call('save', {'value': 3});
      expect(sent[1]['p_operation'], isNot(sent[0]['p_operation']));
    });
  }

  test(
    'lost response and recreated client retry one identity and capture time',
    () async {
      final requests = <Map<String, dynamic>>[];
      var loseResponse = true;
      RetryableRpc client() => RetryableRpc(
        account: 'user-a',
        currentAccount: () => 'user-a',
        send: (_, request) async {
          requests.add(request);
          if (loseResponse) {
            throw TimeoutException('response lost after commit');
          }
          return request['p_operation'];
        },
      );
      await expectLater(
        client().call('record_manual_meter', {
          'p_hours': 120,
        }, captureTime: true),
        throwsA(isA<TimeoutException>()),
      );
      loseResponse = false;
      await client().call('record_manual_meter', {
        'p_hours': 120,
      }, captureTime: true);
      expect(requests[1], requests[0]);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('simultaneous identical save shares one request', () async {
    final release = Completer<void>();
    var sent = 0;
    final client = RetryableRpc(
      account: 'user-a',
      currentAccount: () => 'user-a',
      send: (_, request) async {
        sent++;
        await release.future;
        return request['p_operation'];
      },
    );
    final first = client.call('save', {'b': 2, 'a': 1});
    final second = client.call('save', {'a': 1, 'b': 2});
    release.complete();
    expect(await first, await second);
    expect(sent, 1);
  });

  test(
    'account switch retains the receipt and cannot acknowledge another account',
    () async {
      var account = 'user-a';
      final client = RetryableRpc(
        account: account,
        currentAccount: () => account,
        send: (_, __) async {
          account = 'user-b';
          return 'saved';
        },
      );
      await expectLater(
        client.call('save', {'name': 'A'}),
        throwsA(isA<AccountChangedException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getKeys().single,
        startsWith('account:user-a:'),
      );
    },
  );
}
