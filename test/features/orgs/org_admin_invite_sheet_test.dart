import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_invite_sheet.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/client_capability.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

class _RecordingCodes extends OrgCodeController {
  _RecordingCodes(super.ref);
  final calls = <Map<String, Object?>>[];
  bool success = true;
  Completer<bool>? pending;

  @override
  Future<bool> createCode({
    required String code,
    required String intendedRole,
    required int maxUses,
    required bool singleUse,
    DateTime? expiresAt,
    String? notes,
    String? orgId,
  }) async {
    calls.add({
      'code': code,
      'role': intendedRole,
      'maxUses': maxUses,
      'singleUse': singleUse,
      'orgId': orgId,
      'notes': notes,
      'expiresAt': expiresAt,
    });
    if (pending != null) return pending!.future;
    if (!success) {
      state = AsyncError(StateError('Test failure'), StackTrace.current);
    }
    return success;
  }
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  late _RecordingCodes controller;

  Future<void> pumpSheet(
    WidgetTester tester, {
    bool mechanic = true,
    bool operator = true,
    String locale = 'en',
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientCapabilitiesProvider('owner-1').overrideWith(
            (ref) async => ClientCapabilitySwitchboard(
              clientId: 'owner-1',
              enabledByCapability: {
                ClientCapability.pmChecklists: mechanic,
                ClientCapability.operationalChecklists: operator,
              },
            ),
          ),
          orgCodeControllerProvider.overrideWith(
            (ref) => controller = _RecordingCodes(ref),
          ),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: Key('fleet-capture'),
            child: Scaffold(
              body: OrgAdminInviteSheet(
                orgId: 'org-1',
                ownerProfileId: 'owner-1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Initialize the lazily created controller before a failed validation.
    ProviderScope.containerOf(
      tester.element(find.byType(OrgAdminInviteSheet)),
    ).read(orgCodeControllerProvider);
  }

  Future<void> create(
    WidgetTester tester, {
    String label = 'Create invite code',
  }) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'validates name and optional email then creates a single-use company code',
    (tester) async {
      await pumpSheet(tester);
      await create(tester);
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(controller.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, ' Pat ');
      await tester.enterText(find.byType(TextFormField).last, 'bad-email');
      await create(tester);
      expect(controller.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField).last, '');
      await create(tester);
      expect(controller.calls, hasLength(1));
      expect(controller.calls.single['orgId'], 'org-1');
      expect(controller.calls.single['role'], 'client_mechanic');
      expect(controller.calls.single['singleUse'], true);
      expect(controller.calls.single['maxUses'], 1);
      expect(
        (controller.calls.single['expiresAt']! as DateTime)
            .difference(DateTime.now())
            .inDays,
        6,
      );
      expect(find.text('Invite code created'), findsOneWidget);
      expect(find.textContaining('No email was sent.'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Create invite code'), findsNothing);
    },
  );

  testWidgets('copy writes the created code to the native clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Pat');
    await create(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, controller.calls.single['code']);
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('selects the enabled role and blocks disabled roles', (
    tester,
  ) async {
    await pumpSheet(tester, mechanic: false);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mechanic'))
          .onSelected,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Operator');
    await create(tester);
    expect(controller.calls.single['role'], 'client_operator');
    await pumpSheet(tester, mechanic: false, operator: false);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create invite code'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Share opens the native share request with the saved code', (
    tester,
  ) async {
    final requests = <MethodCall>[];
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requests.add(call);
      return 'dev.fluttercommunity.plus/share/dismissed';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Pat');
    await create(tester);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(
      (requests.single.arguments as Map)['text'],
      contains(controller.calls.single['code']),
    );
    expect(find.text('Invite code created'), findsOneWidget);
    expect(controller.calls, hasLength(1));
  });

  testWidgets(
    'failure preserves input and supports retry without a success claim',
    (tester) async {
      await pumpSheet(tester);
      controller.success = false;
      await tester.enterText(find.byType(TextFormField).first, 'Pat');
      await create(tester);
      expect(find.text('Pat'), findsOneWidget);
      expect(find.text('Invite code created'), findsNothing);
      expect(find.textContaining('Check your connection'), findsOneWidget);
      controller.success = true;
      await create(tester);
      expect(controller.calls, hasLength(2));
      expect(find.text('Invite code created'), findsOneWidget);
    },
  );

  testWidgets('dismissal during create does not update a disposed sheet', (
    tester,
  ) async {
    await pumpSheet(tester);
    controller.pending = Completer<bool>();
    final pending = controller.pending!;
    await tester.enterText(find.byType(TextFormField).first, 'Pat');
    await tester.tap(find.text('Create invite code'));
    await tester.pump();
    expect(controller.calls, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create invite code'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Spanish form and success remain usable at large text on a narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpSheet(tester, locale: 'es', scale: 2);
      await tester.enterText(find.byType(TextFormField).first, 'Pat');
      await create(tester, label: 'Crear código de invitación');
      expect(find.text('Código de invitación creado'), findsOneWidget);
      await tester.ensureVisible(find.text('Compartir'));
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'team-invite-success-es-large');
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'invite form and success render in ${dark ? "dark" : "light"} theme',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpSheet(tester, dark: dark);
        await captureFleet(
          tester,
          'team-invite-form-${dark ? "dark" : "light"}',
        );
        await tester.enterText(find.byType(TextFormField).first, 'Pat');
        await create(tester);
        expect(tester.takeException(), isNull);
        await captureFleet(
          tester,
          'team-invite-success-${dark ? "dark" : "light"}',
        );
      },
    );
  }
}
