import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/db/database.dart';

class HeldCacheWrite extends InMemorySharedPreferencesStore {
  HeldCacheWrite(this.heldKey) : super.empty();
  final String heldKey;
  final started = Completer<void>(), release = Completer<void>();
  bool held = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith(heldKey) && !held) {
      held = true;
      started.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Known permission invalidation fences a read awaiting its final cache write', () async {
    final disk = HeldCacheWrite(accountStorageKey('audit-account', 'cache:provider-context'));
    SharedPreferencesStorePlatform.instance = disk;
    final cache = AccountJsonCache('audit-account', () => 'audit-account');
    final read = cache.readThrough('provider-context', () async => {'notes_internal': 'synthetic provider-only data'});
    await disk.started.future.timeout(const Duration(seconds: 3));
    await invalidateAccountReadCaches('audit-account');
    disk.release.complete();
    Object? error; dynamic result;
    try { result = await read; } catch (e) { error = e; }
    expect(error, isA<AccountChangedException>(),
      reason: 'Known invalidation must reject the in-flight read; received ${result is Map ? result.keys.toList() : result}.');
  });

  test('An account switch fences a read awaiting its final cache write', () async {
    var active = 'audit-account';
    final disk = HeldCacheWrite(accountStorageKey(active, 'cache:provider-context'));
    SharedPreferencesStorePlatform.instance = disk;
    final cache = AccountJsonCache(active, () => active);
    final read = cache.readThrough('provider-context', () async => {'notes_internal': 'synthetic provider-only data'});
    await disk.started.future.timeout(const Duration(seconds: 3));
    active = 'other-account';
    disk.release.complete();
    Object? error; dynamic result;
    try { result = await read; } catch (e) { error = e; }
    expect(error, isA<AccountChangedException>(),
      reason: 'Account switch must reject the in-flight read; received ${result is Map ? result.keys.toList() : result}.');
  });

  test('Future retained schema is rejected without resetting its version or writing data', () async {
    final root = await Directory.systemTemp.createTemp('vortice-retained-schema-audit-');
    final file = File('${root.path}/fixture.sqlite');
    final initial = AppDatabase.forAccount('audit-account', executor: NativeDatabase(file));
    await initial.customSelect('SELECT 1').get();
    await initial.close();
    var raw = sqlite.sqlite3.open(file.path);
    raw.execute('PRAGMA user_version=999');
    raw.execute('CREATE TABLE future_marker(value TEXT)');
    raw.execute("INSERT INTO future_marker VALUES ('synthetic retained marker')");
    raw.dispose();
    final older = AppDatabase.forAccount('audit-account', executor: NativeDatabase(file));
    Object? error;
    try { await older.customSelect('SELECT 1').get(); } catch (e) { error = e; }
    await older.close();
    raw = sqlite.sqlite3.open(file.path);
    final version = raw.select('PRAGMA user_version').single.values.single;
    final marker = raw.select('SELECT value FROM future_marker').single['value'];
    raw.dispose();
    await root.delete(recursive: true);
    expect(error, isNotNull, reason: 'Future schema opened and user_version became $version; retained marker present=${marker != null}.');
    expect(version, 999);
  });
}
