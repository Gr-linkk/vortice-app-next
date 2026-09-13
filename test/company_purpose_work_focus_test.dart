import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/company_purpose.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/maintenance/work_focus.dart';
import 'package:vortice_app/features/maintenance/planning/planning_models.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'purpose defaults distinguish focus without restricting fleet tools',
    () {
      expect(WorkFocus.forPurpose(CompanyPurpose.fleet), WorkFocus.own);
      expect(WorkFocus.forPurpose(CompanyPurpose.service), WorkFocus.customer);
      expect(WorkFocus.forPurpose(CompanyPurpose.both), WorkFocus.all);
      expect(WorkFocus.forPurpose(null), WorkFocus.all);
      for (final purpose in CompanyPurpose.values) {
        final company = OrganizationMembership(
          organizationId: 'org',
          name: 'Test',
          ownerProfileId: 'owner',
          roles: ['company_owner'],
          permissions: [],
          companyPurpose: purpose,
        );
        expect(company.can('assets_manage') && company.can('planning'), isTrue);
      }
    },
  );
  test('outside provider working on our equipment remains own work', () {
    final ours = PlanningJob({
      'id': 'ours',
      'asset_id': 'asset',
      'provider_service': true,
      'own_equipment': true,
    });
    final customer = PlanningJob({
      'id': 'customer',
      'asset_id': 'asset',
      'provider_service': true,
      'own_equipment': false,
    });
    expect(ours.matchesWorkFocus(WorkFocus.own), isTrue);
    expect(ours.matchesWorkFocus(WorkFocus.customer), isFalse);
    expect(customer.matchesWorkFocus(WorkFocus.customer), isTrue);
    expect(customer.matchesWorkFocus(WorkFocus.own), isFalse);
    expect(
      [ours, customer].every((job) => job.matchesWorkFocus(WorkFocus.all)),
      isTrue,
    );
  });
  test(
    'saved work focus survives reopening and stays with account and company',
    () async {
      Future<ProviderContainer> open(
        String account,
        String org,
        CompanyPurpose purpose,
      ) async {
        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(
              (ref) async => Profile(
                id: account,
                email: 'test@example.invalid',
                fullName: 'Test',
                role: UserRole.clientAdmin,
                membershipManaged: true,
                orgId: org,
              ),
            ),
            organizationContextProvider.overrideWith(
              (ref) async => OrganizationContext(
                activeOrganizationId: org,
                memberships: [
                  OrganizationMembership(
                    organizationId: org,
                    name: 'Company',
                    ownerProfileId: account,
                    roles: ['company_owner'],
                    permissions: [],
                    companyPurpose: purpose,
                  ),
                ],
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(workFocusProvider.future);
        return container;
      }

      final first = await open('alice', 'a', CompanyPurpose.service);
      expect(first.read(workFocusProvider).requireValue, WorkFocus.customer);
      await first.read(workFocusProvider.notifier).select(WorkFocus.own);
      expect(
        (await open(
          'alice',
          'a',
          CompanyPurpose.service,
        )).read(workFocusProvider).requireValue,
        WorkFocus.own,
      );
      expect(
        (await open(
          'alice',
          'b',
          CompanyPurpose.both,
        )).read(workFocusProvider).requireValue,
        WorkFocus.all,
      );
      expect(
        (await open(
          'bob',
          'a',
          CompanyPurpose.service,
        )).read(workFocusProvider).requireValue,
        WorkFocus.customer,
      );
    },
  );
  testWidgets(
    'company choices wrap and remain selectable at 320px and 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final es in [false, true]) {
        CompanyPurpose? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CompanyPurposePicker(
                      value: null,
                      spanish: es,
                      onChanged: (v) => selected = v,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('company-purpose-service')),
        );
        await tester.tap(find.byKey(const ValueKey('company-purpose-service')));
        await tester.pumpAndSettle();
        expect(selected, CompanyPurpose.service);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
