import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/agent_access/maintenance_document_importer.dart';
import 'package:vortice_app/features/agent_access/maintenance_documents_repository.dart';
import 'package:vortice_app/features/agent_access/maintenance_documents_screen.dart';
import 'agent_mfa_test.dart' show session;
import '../fleet/fleet_test_support.dart';

class FixtureDocuments extends MaintenanceDocumentsRepository {
  List<Map<String, dynamic>> documents = [];
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<List<Map<String, dynamic>>> list(String fleet) async => documents;
  @override
  Future<Uint8List> page(String document, int page) async =>
      throw StateError('No page');
  @override
  Future<void> save(
    String id,
    String fleet,
    String title,
    List<MaintenanceDocumentPage> pages,
  ) async {
    writes.add({'id': id, 'fleet': fleet, 'title': title, 'pages': pages});
    if (pending != null) await pending!.future;
    if (fail) throw StateError('private backend error');
    documents = [
      {
        'id': id,
        'title': title,
        'maintenance_document_pages': [
          for (var i = 1; i <= pages.length; i++) {'page': i},
        ],
      },
    ];
  }
}

class FixtureImporter extends MaintenanceDocumentImporter {
  FixtureImporter(this.pages);
  final List<MaintenanceDocumentPage> pages;
  @override
  Future<List<MaintenanceDocumentPage>> camera() async => pages;
  @override
  Future<List<MaintenanceDocumentPage>> pdf() async => pages;
  @override
  Future<List<MaintenanceDocumentPage>> photos() async => pages;
}

Widget app(
  FixtureDocuments repo,
  FixtureImporter importer, {
  String actor = 'a',
  bool spanish = false,
  bool dark = false,
  double scale = 1,
}) => RepaintBoundary(
  key: const Key('fleet-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: Locale(spanish ? 'es' : 'en'),
    supportedLocales: const [Locale('en'), Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: MaintenanceDocumentsPanel(
      key: ValueKey(actor),
      repository: repo,
      fleet: 'fleet-$actor',
      fleetName: 'Harbour Marine',
      importer: importer,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MaintenanceDocumentPage page;
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 1000),
      Paint()..color = Colors.white,
    );
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: const TextSpan(
        style: TextStyle(color: Colors.black, fontSize: 28, height: 1.6),
        text:
            'SYNTHETIC TEST MANUAL\nRevision 1 · Page 1\n\nCooling inspection\n\nCheck coolant only when\nthe engine is cold.\n\nTest fixture, not a procedure.',
      ),
    )..layout(maxWidth: 690);
    text.paint(canvas, const Offset(50, 60));
    final image = await recorder.endRecording().toImage(800, 1000);
    page = MaintenanceDocumentPage(
      (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    image.dispose();
    text.dispose();
  });

  testWidgets(
    'scan preview and retry retain immutable pages, title and operation identity',
    (tester) async {
      final repo = FixtureDocuments()..fail = true;
      await tester.pumpWidget(app(repo, FixtureImporter([page])));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Maintenance manual rev 1',
      );
      await tester.tap(find.text('Scan page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Save document'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save document'));
      await tester.pumpAndSettle();
      expect(find.textContaining('same pages and document ID'), findsOneWidget);
      expect(find.textContaining('private backend error'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      repo.fail = false;
      await tester.ensureVisible(find.text('Retry upload'));
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();
      expect(repo.writes.length, 2);
      expect(repo.writes[0], repo.writes[1]);
      expect(find.textContaining('Ask your connected agent'), findsOneWidget);
      await tester.ensureVisible(find.text('Scan another document'));
      await tester.tap(find.text('Scan another document'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change discards an in-flight upload result and page preview',
    (tester) async {
      final old = FixtureDocuments()..pending = Completer<void>();
      await tester.pumpWidget(app(old, FixtureImporter([page])));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private old manual');
      await tester.tap(find.text('Scan page'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Save document'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save document'));
      await tester.pump();
      await tester.pumpWidget(
        app(FixtureDocuments(), FixtureImporter([page]), actor: 'b'),
      );
      old.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Private old manual'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final spanish in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'scan controls at 320px and 200% ${spanish ? 'Spanish' : 'English'} ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            app(
              FixtureDocuments(),
              FixtureImporter([page]),
              spanish: spanish,
              dark: dark,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          await captureFleet(
            tester,
            'scan-${spanish ? 'es' : 'en'}-${dark ? 'dark' : 'light'}',
          );
          await tester.ensureVisible(find.text('PDF'));
          await tester.tap(find.text('PDF'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.text(spanish ? 'Página 1' : 'Page 1'),
          );
          await captureFleet(
            tester,
            'scan-page-${spanish ? 'es' : 'en'}-${dark ? 'dark' : 'light'}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'repository resumes already-uploaded pages without rewriting source objects',
    () async {
      final paths = <String>[];
      final client = SupabaseClient(
        'https://hkjpojobdbbtjkhaudki.supabase.co',
        'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/save_maintenance_document')) {
            return http.Response('', 204, request: request);
          }
          if (request.url.path.endsWith('/list/maintenance-documents')) {
            return http.Response('[{"name":"1.png","id":"page"}]', 200, request: request);
          }
          if (request.url.path.endsWith(
            '/maintenance-documents/document/1.png',
          )) {
            return http.Response.bytes(page.bytes, 200, request: request);
          }
          throw StateError('Unexpected request ${request.url.path}');
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('actor')));
      await SupabaseMaintenanceDocumentsRepository(
        client,
        'actor',
      ).save('document', 'fleet', 'Manual', [page]);
      expect(
        paths.where(
          (p) =>
              p.startsWith('POST') &&
              p.contains('/object/maintenance-documents/'),
        ),
        isEmpty,
      );
      expect(
        paths.where((p) => p.endsWith('/save_maintenance_document')).length,
        2,
      );
    },
  );

  test(
    'repository stops before upload when the account changes during reservation',
    () async {
      final reservation = Completer<http.Response>();
      late http.Request reservationRequest;
      var count = 0;
      final client = SupabaseClient(
        'https://hkjpojobdbbtjkhaudki.supabase.co',
        'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          count++;
          reservationRequest = request;
          return reservation.future;
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('old')));
      final saving = SupabaseMaintenanceDocumentsRepository(
        client,
        'old',
      ).save('document', 'fleet', 'Manual', [page]);
      await Future<void>.delayed(Duration.zero);
      await client.auth.recoverSession(jsonEncode(session('new')));
      final expectation = expectLater(saving, throwsStateError);
      reservation.complete(http.Response('', 204, request: reservationRequest));
      await expectation;
      expect(count, 1);
    },
  );
}
