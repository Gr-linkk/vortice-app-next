import 'dart:convert';
import 'dart:async';
import 'package:vortice_app/core/account_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/maintenance/planning/planning_service_repository.dart';
import 'package:vortice_app/models/work_order.dart';

WorkOrder serviceOrder(
  String id, {
  String? engine,
  String? worker,
  WorkOrderStatus status = WorkOrderStatus.assigned,
}) => WorkOrder(
  id: id,
  assetId: 'asset',
  engineId: engine,
  clientId: 'company',
  createdBy: 'owner',
  title: 'Service $id',
  assignedTo: worker,
  jobType: WorkOrderJobType.inspection,
  status: status,
  scheduledDate: DateTime(2026, 9, 12),
);

http.Response rows(http.Request request, Object data) => http.Response(
  jsonEncode(data),
  200,
  request: request,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> session(String accountId) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': accountId,
            'exp':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return {
    'access_token': 'e30.$payload.signature',
    'refresh_token': 'fixture',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': accountId,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-09-07T12:00:00Z',
    },
  };
}

void main() {
  test(
    'a late assignment response cannot cross the initiating account',
    () async {
      final assignmentStarted = Completer<void>();
      final releaseAssignment = Completer<void>();
      var profileReads = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/work_order_assignments')) {
            assignmentStarted.complete();
            await releaseAssignment.future;
            return rows(request, [
              {
                'id': 'assignment',
                'work_order_id': 'work',
                'profile_id': 'private-worker',
              },
            ]);
          }
          if (request.url.path.endsWith('/profiles')) profileReads++;
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      final pending = SupabasePlanningServiceRepository(
        client,
      ).load([serviceOrder('work')], accountId: 'account-a');
      final failure = expectLater(
        pending,
        throwsA(isA<AccountChangedException>()),
      );
      await assignmentStarted.future;
      await client.auth.recoverSession(jsonEncode(session('account-b')));
      releaseAssignment.complete();
      await failure;
      expect(profileReads, 0);
    },
  );

  test(
    'an already changed account cannot start enrichment for the old profile',
    () async {
      var reads = 0;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          reads++;
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-b')));
      await expectLater(
        SupabasePlanningServiceRepository(
          client,
        ).load([serviceOrder('work')], accountId: 'account-a'),
        throwsA(isA<AccountChangedException>()),
      );
      expect(reads, 0);
    },
  );

  test(
    'an inconsistent legacy component never appears under another asset',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/asset_engines')) {
            expect(request.url.queryParameters['select'], contains('asset_id'));
            return rows(request, [
              {
                'id': 'engine',
                'asset_id': 'other-asset',
                'label': 'Other asset generator',
              },
            ]);
          }
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      final inconsistent = serviceOrder('inconsistent', engine: 'engine');
      final correct = serviceOrder(
        'correct',
        engine: 'engine',
      ).copyWith(assetId: 'other-asset');
      final context = await SupabasePlanningServiceRepository(
        client,
      ).load([inconsistent, correct], accountId: 'account-a');
      expect(
        context.project(inconsistent, 'account-a', '/owner').componentName,
        isEmpty,
      );
      expect(
        context.project(correct, 'account-a', '/owner').componentName,
        'Other asset generator',
      );
    },
  );

  test(
    '80 provider orders use four bulk reads and retain every assignment and route',
    () async {
      final requests = <http.Request>[];
      final orders = [
        for (var i = 0; i < 80; i++)
          serviceOrder(
            'work-$i',
            engine: 'engine',
            worker: 'lead',
            status: i == 79
                ? WorkOrderStatus.invoiced
                : WorkOrderStatus.assigned,
          ),
      ];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return rows(request, switch (request.url.path.split('/').last) {
            'assets' => [
              {'id': 'asset', 'name': 'Harbour generator'},
            ],
            'asset_engines' => [
              {
                'id': 'engine',
                'asset_id': 'asset',
                'label': 'Port hydraulic pump',
              },
            ],
            'work_order_assignments' => [
              for (final order in orders)
                {
                  'id': 'assignment-${order.id}',
                  'work_order_id': order.id,
                  'profile_id': 'secondary',
                },
            ],
            'profiles' => [
              {'id': 'lead', 'full_name': 'Lead mechanic'},
              {'id': 'secondary', 'full_name': 'Alex Morgan'},
            ],
            _ => throw StateError('Unexpected request ${request.url.path}'),
          });
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      final context = await SupabasePlanningServiceRepository(
        client,
      ).load(orders, accountId: 'account-a');
      expect(requests, hasLength(4));
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        requests.map((request) => request.url.path.split('/').last).toSet(),
        {'assets', 'asset_engines', 'work_order_assignments', 'profiles'},
      );
      final assignmentRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/work_order_assignments'),
      );
      expect(
        assignmentRequest.url.queryParameters['work_order_id'],
        contains('work-79'),
      );
      expect(
        assignmentRequest.url.queryParameters['work_order_id'],
        isNot(contains('outside-order')),
      );
      final job = context.project(orders.first, 'secondary', '/employee');
      expect(
        job.matchesFilter('mine', 'secondary', DateTime(2026, 9, 12)),
        isTrue,
      );
      expect(
        job.matchesFilter('unassigned', 'secondary', DateTime(2026, 9, 12)),
        isFalse,
      );
      expect(job.workers.keys, containsAll(['lead', 'secondary']));
      expect(job.matchesSearch('alex', false), isTrue);
      expect(job.componentName, 'Port hydraulic pump');
      expect(job.route, '/employee/work-orders/work-0');
      expect(job.serviceDate, DateTime(2026, 9, 12));
      expect(job.start, isNull);
      final completed = context.project(orders.last, 'owner', '/owner');
      expect(completed.completed, isTrue);
      expect(completed.schedulable, isFalse);
      expect(completed.route, '/owner/work-orders/work-79');
    },
  );

  test(
    'large visible sets use bounded ID chunks without per-order requests',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      await SupabasePlanningServiceRepository(client).load([
        for (var i = 0; i < 205; i++) serviceOrder('work-$i'),
      ], accountId: 'account-a');
      final assignments = requests
          .where(
            (request) => request.url.path.endsWith('/work_order_assignments'),
          )
          .toList();
      expect(assignments, hasLength(3));
      expect(
        requests,
        hasLength(4),
      ); // One shared asset, three assignment batches.
      final batchSizes = assignments
          .map(
            (request) => RegExp(
              r'work-\d+',
            ).allMatches(request.url.queryParameters['work_order_id']!).length,
          )
          .toList();
      expect(batchSizes, [100, 100, 5]);
    },
  );

  test(
    'assignment pagination retains workers beyond the first server page',
    () async {
      final assignmentOffsets = <int>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/work_order_assignments')) {
            final offset = int.parse(
              request.url.queryParameters['offset'] ?? '0',
            );
            assignmentOffsets.add(offset);
            return rows(request, [
              for (var i = offset; i < (offset == 0 ? 500 : 501); i++)
                {
                  'id': 'assignment-$i',
                  'work_order_id': 'work',
                  'profile_id': 'worker-$i',
                },
            ]);
          }
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      final order = serviceOrder('work');
      final context = await SupabasePlanningServiceRepository(
        client,
      ).load([order], accountId: 'account-a');
      expect(assignmentOffsets, [0, 500]);
      final job = context.project(order, 'worker-500', '/employee');
      expect(job.workers, hasLength(501));
      expect(
        job.matchesFilter('mine', 'worker-500', DateTime(2026, 9, 12)),
        isTrue,
      );
    },
  );

  test(
    'legacy primary assignment and unassigned work retain their meanings',
    () {
      const context = PlanningServiceData(workerNames: {'mechanic': 'Alex'});
      final primary = context.project(
        serviceOrder('primary', worker: 'mechanic'),
        'mechanic',
        '/employee',
      );
      final unassigned = context.project(
        serviceOrder('unassigned'),
        'mechanic',
        '/employee',
      );
      expect(
        primary.matchesFilter('mine', 'mechanic', DateTime(2026, 9, 12)),
        isTrue,
      );
      expect(
        unassigned.matchesFilter('mine', 'mechanic', DateTime(2026, 9, 12)),
        isFalse,
      );
      expect(
        unassigned.matchesFilter(
          'unassigned',
          'mechanic',
          DateTime(2026, 9, 12),
        ),
        isTrue,
      );
    },
  );

  test('empty visible set performs no enrichment reads', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient(
        (request) async => throw StateError('Unexpected request'),
      ),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(jsonEncode(session('account-a')));
    final context = await SupabasePlanningServiceRepository(
      client,
    ).load([], accountId: 'account-a');
    expect(context.assetNames, isEmpty);
    expect(context.workersByOrder, isEmpty);
  });

  test(
    'denied enrichment fails visibly instead of claiming missing workers',
    () async {
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/work_order_assignments')) {
            return http.Response(
              jsonEncode({'code': '42501', 'message': 'permission denied'}),
              403,
              headers: {'content-type': 'application/json'},
            );
          }
          return rows(request, []);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(session('account-a')));
      await expectLater(
        SupabasePlanningServiceRepository(
          client,
        ).load([serviceOrder('work')], accountId: 'account-a'),
        throwsA(isNotNull),
      );
    },
  );
}
