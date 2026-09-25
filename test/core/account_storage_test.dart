import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('cached context survives restart only for its account', () async {
    String? active = 'a';
    await AccountJsonCache(
      'a',
      () => active,
    ).readThrough('job', () async => {'title': 'private A'});
    Future<dynamic> offline() async => throw TimeoutException('offline');
    expect(
      await AccountJsonCache('a', () => active).readThrough('job', offline),
      {'title': 'private A'},
    );
    active = 'b';
    await expectLater(
      AccountJsonCache('b', () => active).readThrough('job', offline),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      AccountJsonCache('a', () => active).readThrough('job', offline),
      throwsA(isA<AccountChangedException>()),
    );
    active = 'a';
    expect(
      await AccountJsonCache('a', () => active).readThrough('job', offline),
      {'title': 'private A'},
    );
  });
  test('late response and server denial never reveal cached work', () async {
    String? active = 'a';
    final cache = AccountJsonCache('a', () => active);
    await cache.readThrough('job', () async => 'old');
    await expectLater(
      cache.readThrough(
        'job',
        () async =>
            throw const PostgrestException(message: 'Denied', code: '42501'),
      ),
      throwsA(isA<PostgrestException>()),
    );
    final response = Completer<dynamic>();
    final pending = cache.readThrough('job', () => response.future);
    await Future<void>.delayed(Duration.zero);
    active = 'b';
    final assertion = expectLater(
      pending,
      throwsA(isA<AccountChangedException>()),
    );
    response.complete('late');
    await assertion;
    active = 'a';
    await expectLater(
      cache.readThrough('job', () async => throw TimeoutException('offline')),
      throwsA(isA<TimeoutException>()),
    );
  });
  test(
    'an invalidated read retries fresh, but never crosses accounts or masks denial',
    () async {
      String? active = 'a';
      final cache = AccountJsonCache('a', () => active);
      var calls = 0;
      final result = await retryInvalidatedAccountRead(
        account: 'a',
        currentAccount: () => active,
        read: () async {
          if (++calls == 1) throw const AccountChangedException();
          return cache.readThrough('job', () async => 'fresh permitted job');
        },
      );
      expect(result, 'fresh permitted job');
      expect(calls, 2);
      calls = 0;
      await expectLater(
        retryInvalidatedAccountRead(
          account: 'a',
          currentAccount: () => active,
          read: () async {
            if (++calls == 1) throw const AccountChangedException();
            return cache.readThrough(
              'job',
              () async => throw TimeoutException('offline'),
            );
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      calls = 0;
      await expectLater(
        retryInvalidatedAccountRead(
          account: 'a',
          currentAccount: () => active,
          read: () async {
            calls++;
            active = 'b';
            throw const AccountChangedException();
          },
        ),
        throwsA(isA<AccountChangedException>()),
      );
      expect(calls, 1);
      active = 'a';
      calls = 0;
      await expectLater(
        retryInvalidatedAccountRead(
          account: 'a',
          currentAccount: () => active,
          read: () async {
            calls++;
            throw const PostgrestException(message: 'Denied', code: '42501');
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    },
  );
  test('account paths cannot alias or traverse another database', () {
    expect(accountDatabaseName('a'), isNot(accountDatabaseName('b')));
    expect(() => accountDatabaseName('../a'), throwsArgumentError);
    expect(
      accountStorageKey('a', 'draft'),
      isNot(accountStorageKey('b', 'draft')),
    );
  });
  test('expiry and authoritative removals preserve drafts', () async {
    var time = DateTime.utc(2026, 1, 1);
    final cache = AccountJsonCache('a', () => 'a', now: () => time);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accountStorageKey('a', 'draft'), 'unsent');
    await cache.readThrough(
      'list',
      () async => ['one'],
      derivedValues: (_) => {'item:one': 1},
      replaceDerivedPrefix: 'item:',
    );
    await cache.readThrough(
      'list',
      () async => [],
      replaceDerivedPrefix: 'item:',
    );
    expect(prefs.containsKey(accountStorageKey('a', 'cache:item:one')), false);
    time = time.add(const Duration(hours: 25));
    await expectLater(
      cache.readThrough('list', () async => throw TimeoutException('offline')),
      throwsA(isA<TimeoutException>()),
    );
    await invalidateAccountReadCaches('a');
    expect(prefs.getString(accountStorageKey('a', 'draft')), 'unsent');
  });
}
