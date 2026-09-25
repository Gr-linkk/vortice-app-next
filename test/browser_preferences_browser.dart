@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:web/web.dart' as web;
import 'package:vortice_app/core/browser/preferences_web.dart';

void main() {
  test(
    'large account drafts commit, reopen, and clear only the selected account',
    () async {
      final name = 'vortice_test_${DateTime.now().microsecondsSinceEpoch}';
      final first = await BrowserPreferences.open(
        name: name,
        migrateLegacy: false,
      );
      final draft = List.filled(6 * 1024 * 1024, 'x').join();
      await first.setValue('String', 'flutter.account:a:draft', draft);
      await first.setValue('Int', 'flutter.account:b:revision', 42);
      await first.setValue('StringList', 'flutter.languages', ['en', 'fr']);
      first.close();
      final reopened = await BrowserPreferences.open(
        name: name,
        migrateLegacy: false,
      );
      final stored = await reopened.getAll();
      expect(stored['flutter.account:a:draft'], draft);
      expect(stored['flutter.languages'], ['en', 'fr']);
      await reopened.clearWithParameters(
        ClearParameters(
          filter: PreferencesFilter(prefix: 'flutter.account:a:'),
        ),
      );
      expect(
        (await reopened.getAll()).containsKey('flutter.account:a:draft'),
        isFalse,
      );
      expect((await reopened.getAll())['flutter.account:b:revision'], 42);
      await reopened.clear();
      reopened.close();
      web.window.indexedDB.deleteDatabase(name);
    },
  );

  test(
    'legacy browser draft migrates without overwriting a newer committed value',
    () async {
      final name = 'vortice_migration_${DateTime.now().microsecondsSinceEpoch}';
      final first = await BrowserPreferences.open(
        name: name,
        migrateLegacy: false,
      );
      await first.setValue('String', 'flutter.migration_draft', 'newer');
      first.close();
      web.window.localStorage.setItem(
        'flutter.migration_draft',
        jsonEncode('older'),
      );
      web.window.localStorage.setItem(
        'flutter.migration_locale',
        jsonEncode('fr'),
      );
      web.window.localStorage.setItem('unrelated_test', 'keep');
      final migrated = await BrowserPreferences.open(name: name);
      expect((await migrated.getAll())['flutter.migration_draft'], 'newer');
      expect((await migrated.getAll())['flutter.migration_locale'], 'fr');
      expect(
        web.window.localStorage.getItem('flutter.migration_locale'),
        isNull,
      );
      expect(web.window.localStorage.getItem('unrelated_test'), 'keep');
      await migrated.clear();
      migrated.close();
      web.window.localStorage.removeItem('unrelated_test');
      web.window.indexedDB.deleteDatabase(name);
    },
  );
}
