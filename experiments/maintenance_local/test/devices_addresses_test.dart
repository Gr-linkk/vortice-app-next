import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/device_authority.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/ui/devices_page.dart';

class EmptyAuthority implements DeviceAuthority {
  @override
  List<Map<String, dynamic>> get phones => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class InvitationServer implements OfficeServer {
  final created = <String>[];
  bool fail = false;
  @override
  final authority = EmptyAuthority();
  @override
  String invitation(String host) {
    if (fail) throw StateError('Synthetic failure');
    created.add(host);
    return 'private invitation for $host';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final refresh = find.byKey(const ValueKey('refresh-addresses'));
  final create = find.byKey(const ValueKey('create-invitation'));
  late InvitationServer server;
  setUp(() => server = InvitationServer());

  Future<void> open(
    WidgetTester tester,
    Future<List<String>> Function() loader,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DevicesPage(server: server, addressLoader: loader),
      ),
    );
    await tester.pump();
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('fresh open, selection, deduplication and changed address', (
    tester,
  ) async {
    var current = [
      '192.168.1.2',
      '192.168.1.3',
      '192.168.1.3',
      '127.0.0.1',
      '8.8.8.8',
      '::1',
      '169.254.1.2',
      'not-an-address',
    ];
    var loads = 0;
    Future<List<String>> loader() async {
      loads++;
      return current;
    }

    await open(tester, loader);
    var field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .items!
          .map((e) => e.value),
      ['192.168.1.2', '192.168.1.3'],
    );
    await click(tester, find.byType(DropdownButtonFormField<String>));
    await click(tester, find.text('192.168.1.3').last);
    current = ['192.168.1.4', '192.168.1.3'];
    await click(tester, refresh);
    field = tester.widget(find.byType(DropdownButtonFormField<String>));
    expect(field.initialValue, '192.168.1.3');
    await click(tester, create);
    expect(server.created, ['192.168.1.3']);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    await click(tester, find.text('Copy invitation'));
    expect(
      find.textContaining('Invitation copied on this computer only.'),
      findsOneWidget,
    );
    current = ['192.168.1.4'];
    await click(tester, refresh);
    field = tester.widget(find.byType(DropdownButtonFormField<String>));
    expect(field.initialValue, '192.168.1.4');
    expect(find.text('Copy invitation'), findsNothing);
    expect(
      find.textContaining('Invitation copied on this computer only.'),
      findsNothing,
    );
    expect(server.created, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await open(tester, loader);
    expect(loads, 5);
    expect(find.text('192.168.1.4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'repeated refresh ignores older completions and resume rechecks',
    (tester) async {
      final calls = <Completer<List<String>>>[];
      Future<List<String>> loader() {
        final call = Completer<List<String>>();
        calls.add(call);
        return call.future;
      }

      await open(tester, loader);
      await click(tester, refresh);
      await click(tester, refresh);
      calls[2].complete(['10.1.1.3']);
      await tester.pump();
      calls[0].complete(['10.1.1.1']);
      calls[1].complete(['10.1.1.2']);
      await tester.pump();
      expect(find.text('10.1.1.3'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 11));
      expect(calls, hasLength(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      calls[3].complete(['10.1.1.4']);
      await tester.pump();
      expect(find.text('10.1.1.4'), findsOneWidget);
      expect(server.created, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('create revalidates and refresh failure blocks stale creation', (
    tester,
  ) async {
    var current = ['192.168.2.2'];
    var fail = false;
    Future<List<String>> loader() async {
      if (fail) throw StateError('Synthetic read failure');
      return current;
    }

    await open(tester, loader);
    current = ['192.168.2.3'];
    await click(tester, create);
    expect(server.created, isEmpty);
    expect(find.textContaining('Check the address below'), findsOneWidget);
    fail = true;
    await click(tester, refresh);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    fail = false;
    await click(tester, refresh);
    server.fail = true;
    await click(tester, create);
    expect(
      find.textContaining('Could not create an invitation.'),
      findsOneWidget,
    );
    expect(find.text('Copy invitation'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'foreground address change clears invitation without creating another',
    (tester) async {
      var current = ['10.2.2.2'];
      await open(tester, () async => current);
      await click(tester, create);
      expect(server.created, ['10.2.2.2']);
      current = [];
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('Copy invitation'), findsNothing);
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(server.created, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resume supersedes pending create address check', (tester) async {
    final calls = <Completer<List<String>>>[];
    await open(tester, () {
      final call = Completer<List<String>>();
      calls.add(call);
      return call.future;
    });
    calls[0].complete(['10.3.3.2']);
    await tester.pump();
    await tester.pump();
    await click(tester, create);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    calls[2].complete(['10.3.3.3']);
    await tester.pump();
    calls[1].complete(['10.3.3.2']);
    await tester.pump();
    expect(server.created, isEmpty);
    expect(find.text('10.3.3.3'), findsOneWidget);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
