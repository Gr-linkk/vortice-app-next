import 'dart:async';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/sync/offline_readiness.dart';
import 'package:vortice_app/sync/field_sync_status.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('offline readiness banner labels cover French, Spanish and English', () {
    expect(
      offlineReadinessLabel(
        const OfflineReadiness(refreshing: true),
        false,
        french: true,
      ),
      'Mise à jour des données hors ligne',
    );
    expect(
      offlineReadinessLabel(const OfflineReadiness(refreshing: true), true),
      'Actualizando datos sin conexión',
    );
    expect(
      offlineReadinessLabel(const OfflineReadiness(refreshing: true), false),
      'Updating offline data',
    );
    expect(
      offlineReadinessLabel(
        const OfflineReadiness(needsAttention: true),
        false,
        french: true,
      ),
      'Les données hors ligne nécessitent une attention.',
    );
  });
  test(
    'offline preparation excludes out-of-scope pages but keeps pinned assignments',
    () {
      const asset = Asset(
        id: 'asset-a',
        clientId: 'company-a',
        assetTypeId: 'type-a',
        name: 'Equipment',
      );
      final templates = [
        const ChecklistTemplate(id: 'shared', name: 'Shared'),
        const ChecklistTemplate(
          id: 'ours',
          name: 'Ours',
          clientId: 'company-a',
          scopeAssetId: 'asset-a',
        ),
        const ChecklistTemplate(
          id: 'other-company',
          name: 'Other',
          clientId: 'company-b',
        ),
        const ChecklistTemplate(
          id: 'other-asset',
          name: 'Other',
          scopeAssetId: 'asset-b',
        ),
        const ChecklistTemplate(
          id: 'other-type',
          name: 'Other',
          assetTypeId: 'type-b',
        ),
        const ChecklistTemplate(
          id: 'component',
          name: 'Component',
          scopeEngineId: 'engine',
        ),
        const ChecklistTemplate(id: 'retired', name: 'Old', isActive: false),
      ];
      expect(
        offlineChecklistTemplateIds(
          templates,
          [
            {
              'status': 'in_progress',
              'checklist_templates': {'id': 'retired'},
            },
            {
              'status': 'completed',
              'checklist_templates': {'id': 'finished'},
            },
          ],
          [asset],
        ),
        {'shared', 'ours', 'retired'},
      );
      expect(offlineChecklistTemplateIds(templates, [], []), isEmpty);
    },
  );
  test(
    'fresh refresh rejects fallback without changing the existing cache',
    () async {
      const cache = AccountJsonCache('a', accountA);
      await cache.readThrough('asset', () async => {'id': 'one'});
      Future<dynamic> offline() => Future.error(TimeoutException('offline'));
      expect(await cache.readThrough('asset', offline), {'id': 'one'});
      await expectLater(
        withFreshAccountReads(() => cache.readThrough('asset', offline)),
        throwsA(isA<TimeoutException>()),
      );
      expect(await cache.readThrough('asset', offline), {'id': 'one'});
    },
  );
  test(
    'successful ordinary warm persists readiness across restart and expires',
    () async {
      var now = DateTime.utc(2026, 9, 12);
      final controller = OfflineReadinessController(
        account: 'a',
        currentAccount: accountA,
        now: () => now,
        refreshRecords: (check) async {
          check();
        },
      );
      await controller.refresh();
      expect(controller.state.readyAt(now), isTrue);
      final reopened = OfflineReadinessController(
        account: 'a',
        currentAccount: accountA,
        refreshRecords: (_) async {},
      );
      await reopened.restore();
      expect(reopened.state.updatedAt, now);
      now = now.add(const Duration(hours: 24));
      expect(reopened.state.readyAt(now), isFalse);
      controller.dispose();
      reopened.dispose();
    },
  );
  test(
    'partial offline refresh keeps last successful time and throttles retries',
    () async {
      var now = DateTime.utc(2026, 9, 12);
      var attempts = 0;
      final controller = OfflineReadinessController(
        account: 'a',
        currentAccount: accountA,
        now: () => now,
        refreshRecords: (_) async {
          if (++attempts > 1) throw TimeoutException('offline');
        },
      );
      await controller.refresh();
      final first = controller.state.updatedAt;
      now = now.add(const Duration(minutes: 6));
      await controller.refresh();
      await controller.refresh();
      expect(attempts, 2);
      expect(controller.state.updatedAt, first);
      expect(controller.state.needsAttention, isFalse);
      controller.dispose();
    },
  );
  test(
    'permission epoch change cannot publish readiness or erase drafts',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(accountStorageKey('a', 'draft'), 'saved work');
      final controller = OfflineReadinessController(
        account: 'a',
        currentAccount: accountA,
        refreshRecords: (_) async {
          await invalidateAccountReadCaches('a');
        },
      );
      await controller.refresh();
      expect(controller.state.updatedAt, isNull);
      expect(
        prefs.getString(accountStorageKey('a', 'cache:offline_readiness')),
        isNull,
      );
      expect(prefs.getString(accountStorageKey('a', 'draft')), 'saved work');
      controller.dispose();
    },
  );
  test(
    'account switch during refresh cannot publish prior account readiness',
    () async {
      var account = 'a';
      final pending = Completer<void>();
      final controller = OfflineReadinessController(
        account: 'a',
        currentAccount: () => account,
        refreshRecords: (_) => pending.future,
      );
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      account = 'b';
      pending.complete();
      await refresh;
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(accountStorageKey('a', 'cache:offline_readiness')),
        isNull,
      );
      expect(
        prefs.getString(accountStorageKey('b', 'cache:offline_readiness')),
        isNull,
      );
      controller.dispose();
    },
  );
}

String accountA() => 'a';
