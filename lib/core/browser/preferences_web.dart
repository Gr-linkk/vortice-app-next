import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:web/web.dart' as web;

/// Browser preferences include account caches and report drafts, which exceed
/// localStorage's small quota. IndexedDB commits each change before success.
class BrowserPreferences extends SharedPreferencesStorePlatform {
  BrowserPreferences._(this._db);
  final web.IDBDatabase _db;
  static const _store = 'preferences';

  static Future<BrowserPreferences> open({
    String name = 'vortice_preferences',
    bool migrateLegacy = true,
  }) async {
    final request = web.window.indexedDB.open(name, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    final db = await _request(request) as web.IDBDatabase;
    final store = BrowserPreferences._(db);
    if (migrateLegacy) {
      final previous = await store.getAll();
      final local = web.window.localStorage;
      final keys = [
        for (var i = 0; i < local.length; i++)
          if (local.key(i)?.startsWith('flutter.') == true) local.key(i)!,
      ];
      for (final key in keys) {
        if (!previous.containsKey(key)) {
          final value = jsonDecode(local.getItem(key)!) as Object;
          await store.setValue('', key, value);
        }
        // Remove a legacy copy only after its durable destination exists.
        local.removeItem(key);
      }
    }
    return store;
  }

  static Future<JSAny?> _request(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => result.completeError(
      StateError(request.error?.message ?? 'Browser storage request failed'),
    )).toJS;
    return result.future;
  }

  Future<T> _run<T>(
    String mode,
    Future<T> Function(web.IDBObjectStore store) body,
  ) async {
    final tx = _db.transaction(_store.toJS, mode);
    final committed = Completer<void>();
    tx.oncomplete = ((web.Event _) => committed.complete()).toJS;
    tx.onabort = ((web.Event _) => committed.completeError(
      StateError(tx.error?.message ?? 'Browser storage transaction failed'),
    )).toJS;
    // Observe both futures even if a request fails before the transaction aborts.
    final results = await Future.wait<Object?>([
      body(tx.objectStore(_store)),
      committed.future,
    ]);
    return results.first as T;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _run('readwrite', (store) async {
        await _request(store.put(jsonEncode(value).toJS, key.toJS));
        return true;
      });

  @override
  Future<bool> remove(String key) => _run('readwrite', (store) async {
    await _request(store.delete(key.toJS));
    return true;
  });

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _run('readonly', (store) async {
    final results = await Future.wait([
      _request(store.getAllKeys()),
      _request(store.getAll()),
    ]);
    final keys = (results[0] as JSArray).toDart;
    final values = (results[1] as JSArray).toDart;
    final filter = parameters.filter;
    return {
      for (var i = 0; i < keys.length; i++)
        if ((keys[i] as JSString).toDart.startsWith(filter.prefix) &&
            (filter.allowList == null ||
                filter.allowList!.contains((keys[i] as JSString).toDart)))
          (keys[i] as JSString).toDart:
              jsonDecode((values[i] as JSString).toDart) as Object,
    };
  });

  @override
  Future<bool> clear() => clearWithPrefix('flutter.');

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final keys = (await getAllWithParameters(
      GetAllParameters(filter: parameters.filter),
    )).keys;
    for (final key in keys) {
      await remove(key);
    }
    return true;
  }

  void close() => _db.close();
}

Future<void> initializeBrowserPreferences() async {
  SharedPreferencesStorePlatform.instance = await BrowserPreferences.open();
}
