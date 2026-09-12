// Explicit connected internal-build check; changes sessions, not fleet records.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/operator/operator_checklist_draft_store.dart';
import 'connected_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'configured profiles switch through native UI and keep account-owned drafts',
    (tester) async {
      await tester.runAsync(() async {
        final h = ConnectedHarness(tester, report: 'next002-account-switch');
        await h.start();
        Future<void> waitForAccount(String email, String role) async {
          for (var n = 0; n < 150; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final profile = h.container.read(profileProvider).valueOrNull;
            if (supabase.auth.currentUser?.email == email &&
                profile?.email == email) {
              expect(profile!.role.name, role);
              await h.settle();
              return;
            }
          }
          fail('Account switch did not reach the selected profile');
        }

        Future<void> choose(
          String email,
          String role, {
          bool fromLogin = false,
        }) async {
          if (fromLogin) {
            await h.tap(find.byKey(const ValueKey('dev-sign-in')));
          } else {
            await h.go('/more');
            await h.tap(find.byKey(const ValueKey('dev-switch-account')));
          }
          await h.tap(find.byKey(ValueKey('dev-account:$email')));
          await waitForAccount(email, role);
        }

        try {
          await h.step('login picker signs into provider owner', () async {
            await choose('owner@vortice.dev', 'owner', fromLogin: true);
          });
          expect(h.issues, isEmpty);
          final ownerId = supabase.auth.currentUser!.id;
          final ownerDrafts = OperatorChecklistDraftStore(
            ownerId,
            () => supabase.auth.currentUser?.id,
          );
          await ownerDrafts.save({
            'assetId': 'local-fixture-asset',
            'templateId': 'local-fixture-template',
            'operation_id': 'local-account-switch-fixture',
            'started_at': '2026-09-12T06:00:00Z',
            'notes': 'Keep this local test draft with its original account',
          });
          for (final account in const {
            'tech@vortice.dev': 'employee',
            'paradise@vortice.dev': 'clientAdmin',
            'client_mechanic@vortice.dev': 'clientMechanic',
            'operator@vortice.dev': 'operator',
            'client@vortice.dev': 'client',
          }.entries) {
            await h.step(
              'More switches to ${account.value} with isolated saved work',
              () async {
                await choose(account.key, account.value);
                final id = supabase.auth.currentUser!.id;
                final drafts = await OperatorChecklistDraftStore(
                  id,
                  () => supabase.auth.currentUser?.id,
                ).list();
                expect(
                  drafts.any(
                    (d) => d['operation_id'] == 'local-account-switch-fixture',
                  ),
                  isFalse,
                );
                await expectLater(
                  ownerDrafts.list(),
                  throwsA(isA<Exception>()),
                );
              },
            );
            expect(h.issues, isEmpty);
          }
          await h.step(
            'returning to owner restores its original local draft',
            () async {
              await choose('owner@vortice.dev', 'owner');
              final drafts = await ownerDrafts.list();
              expect(
                drafts.single['notes'],
                'Keep this local test draft with its original account',
              );
              await h.go('/more');
              await h.tap(find.byKey(const ValueKey('dev-switch-account')));
              await h.screenshot('dev-switcher-connected-owner');
              expect(tester.takeException(), isNull);
            },
          );
          expect(h.issues, isEmpty);
        } finally {
          await h.close();
        }
      });
    },
  );
}
