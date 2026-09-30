import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:vortice_app/core/account_storage.dart';

// Hold one real preference operation; no timing assumptions or transport.
class _HeldPreferences extends InMemorySharedPreferencesStore {
  _HeldPreferences(this.operation, [this.key]) : super.empty();
  final String operation;
  final String? key;
  final started = Completer<void>();
  final release = Completer<void>();
  bool armed = true;
  bool held = false;

  Future<void> _hold(String operation, [String? key]) async {
    if (armed &&
        !held &&
        this.operation == operation &&
        (this.key == null || key!.endsWith(this.key!))) {
      held = true;
      started.complete();
      await release.future;
    }
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    await _hold('write', key);
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    await _hold('remove', key);
    return super.remove(key);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    await _hold('load');
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _HeldPreferences hold(String operation, [String? key]) {
    final store = _HeldPreferences(operation, key);
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    return store;
  }

  test('account switch during preference load prevents remote fetch', () async {
    var active = 'a';
    var fetches = 0;
    final store = hold('load');
    final read = AccountJsonCache('a', () => active).readThrough(
      'job',
      () async {
        fetches++;
        return {'notes_internal': 'private'};
      },
    );
    final assertion = expectLater(
      read,
      throwsA(isA<AccountChangedException>()),
    );
    await store.started.future.timeout(const Duration(seconds: 3));
    active = 'b';
    store.release.complete();
    await assertion;
    expect(fetches, 0);
  });

  for (final boundary in ['save', 'derived write', 'derived removal']) {
    for (final change in ['account', 'permission']) {
      test('$change change fences $boundary completion', () async {
        var active = 'a';
        final key = accountStorageKey(
          'a',
          boundary == 'save' ? 'cache:profile' : 'cache:item:old',
        );
        final store = hold(
          boundary == 'derived removal' ? 'remove' : 'write',
          key,
        )..armed = false;
        final cache = AccountJsonCache('a', () => active);
        await cache.save('item:old', {'id': 'old'});
        store.armed = true;
        final Future<dynamic> pending = boundary == 'save'
            ? cache.save('profile', {'role': 'member'})
            : cache.readThrough(
                'list',
                () async => [
                  {'id': 'new'},
                ],
                derivedValues: (_) => boundary == 'derived write'
                    ? {
                        'item:old': {'notes_internal': 'private'},
                      }
                    : {
                        'item:new': {'id': 'new'},
                      },
                replaceDerivedPrefix: 'item:',
              );
        final assertion = expectLater(
          pending,
          throwsA(isA<AccountChangedException>()),
        );
        await store.started.future.timeout(const Duration(seconds: 3));
        if (change == 'account') {
          active = 'b';
        } else {
          await invalidateAccountReadCaches('a');
        }
        store.release.complete();
        await assertion;
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(accountStorageKey('a', 'cache:list')), false);
      });
    }
  }

  for (final key in ['organization_context', 'jobs']) {
    test(
      'concurrent invalidation is not adopted during $key refresh',
      () async {
        final store = hold('remove', accountStorageKey('a', 'cache:$key'))
          ..armed = false;
        final cache = AccountJsonCache('a', () => 'a');
        final dynamic old = key == 'jobs'
            ? [
                {'id': 'old'},
              ]
            : {'org_id': 'old'};
        final dynamic fresh = key == 'jobs' ? <dynamic>[] : {'org_id': 'new'};
        await cache.save(key, old);
        store.armed = true;
        final read = cache.readThrough(key, () async => fresh);
        final assertion = expectLater(
          read,
          throwsA(isA<AccountChangedException>()),
        );
        await store.started.future.timeout(const Duration(seconds: 3));
        // The read has advanced to epoch 1 and is clearing stale records.
        // A second, independent permission change advances it to epoch 2.
        await invalidateAccountReadCaches('a');
        store.release.complete();
        await assertion;
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(accountStorageKey('a', 'read_epoch')), 2);
        expect(prefs.containsKey(accountStorageKey('a', 'cache:$key')), false);
      },
    );
  }

  test(
    'old offline read cannot use cache repopulated after invalidation',
    () async {
      final cache = AccountJsonCache('a', () => 'a');
      await cache.save('job', {'notes_internal': 'old'});
      final fetched = Completer<dynamic>();
      final started = Completer<void>();
      final read = cache.readThrough('job', () {
        started.complete();
        return fetched.future;
      });
      final assertion = expectLater(
        read,
        throwsA(isA<AccountChangedException>()),
      );
      await started.future;
      await invalidateAccountReadCaches('a');
      await cache.readThrough('job', () async => {'notes_internal': 'new'});
      fetched.completeError(TimeoutException('offline'));
      await assertion;
      expect(
        await cache.readThrough(
          'job',
          () async => throw TimeoutException('offline'),
        ),
        {'notes_internal': 'new'},
      );
    },
  );

  final selfInvalidations = <String, List<dynamic>>{
    'profile': [
      {'role': 'owner', 'org_id': 'old'},
      {'role': 'member', 'org_id': 'new'},
    ],
    'current_org': [
      {'id': 'old'},
      {'id': 'new'},
    ],
    'organization_context': [
      {'org_id': 'old'},
      {'org_id': 'new'},
    ],
    'capabilities:company': [
      {'edit': true},
      {'edit': false},
    ],
    'jobs': [
      [
        {'id': 'old'},
      ],
      <dynamic>[],
    ],
    'job': [
      {'id': 'old'},
      null,
    ],
  };
  for (final entry in selfInvalidations.entries) {
    test(
      'successful ${entry.key} refresh preserves its own epoch rotation',
      () async {
        final cache = AccountJsonCache('a', () => 'a');
        await cache.save(entry.key, entry.value[0]);
        await cache.save('unrelated', 'stale private context');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(accountStorageKey('a', 'draft'), 'unsent');
        await prefs.setString(
          accountStorageKey('b', 'cache:job'),
          'other account',
        );
        expect(
          await cache.readThrough(entry.key, () async => entry.value[1]),
          entry.value[1],
        );
        expect(prefs.getInt(accountStorageKey('a', 'read_epoch')), 1);
        final stored =
            jsonDecode(
                  prefs.getString(
                    accountStorageKey('a', 'cache:${entry.key}'),
                  )!,
                )
                as Map;
        expect(stored['epoch'], 1);
        expect(
          prefs.containsKey(accountStorageKey('a', 'cache:unrelated')),
          false,
        );
        expect(prefs.getString(accountStorageKey('a', 'draft')), 'unsent');
        expect(
          prefs.getString(accountStorageKey('b', 'cache:job')),
          'other account',
        );
        expect(
          await cache.readThrough(
            entry.key,
            () async => throw TimeoutException('offline'),
          ),
          entry.value[1],
        );
      },
    );
  }

  test(
    'fresh reads reject fallback while ordinary reads retain cache freshness',
    () async {
      final now = DateTime.utc(2026, 9, 30);
      final cache = AccountJsonCache('a', () => 'a', now: () => now);
      await cache.save('job', {'id': 'job'});
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(accountStorageKey('a', 'cache:job'));
      Future<dynamic> offline() async => throw TimeoutException('offline');
      expect(await cache.readThrough('job', offline), {'id': 'job'});
      await expectLater(
        withFreshAccountReads(() => cache.readThrough('job', offline)),
        throwsA(isA<TimeoutException>()),
      );
      expect(prefs.getString(accountStorageKey('a', 'cache:job')), stored);
    },
  );
}
