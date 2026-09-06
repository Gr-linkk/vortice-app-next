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
    expect(
      await cache.readThrough(
        'job',
        () async => throw TimeoutException('offline'),
      ),
      'old',
    );
  });
  test('account paths cannot alias or traverse another database', () {
    expect(accountDatabaseName('a'), isNot(accountDatabaseName('b')));
    expect(() => accountDatabaseName('../a'), throwsArgumentError);
    expect(
      accountStorageKey('a', 'draft'),
      isNot(accountStorageKey('b', 'draft')),
    );
  });
}
