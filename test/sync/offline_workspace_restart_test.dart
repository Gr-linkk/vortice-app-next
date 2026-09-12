import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/assets/asset_workspace.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/checklist_procedure_source.dart';
import 'package:vortice_app/features/checklists/work_order_checklist_snapshot_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/planning/planning_repository.dart';
import 'package:vortice_app/features/maintenance/work_list_provider.dart';
import 'package:vortice_app/features/operator/operator_checklist_draft_store.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_repository.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/sync/offline_readiness.dart';

Map<String, dynamic> _session(String account) {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': account, 'exp': exp})))
      .replaceAll('=', '');
  return {
    'access_token': 'e30.$payload.signature',
    'refresh_token': 'fixture',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': account,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-09-12T00:00:00Z',
    },
  };
}

final _asset = <String, dynamic>{
  'id': 'asset-a',
  'client_id': 'owner-a',
  'asset_type_id': 'type-a',
  'name': 'Field truck',
  'meter_unit': 'km',
};
final _item = <String, dynamic>{
  'id': 'item-retired',
  'template_id': 'retired',
  'description_en': 'Check pressure while stopped',
  'sort_order': 0,
  'definition': {
    'authored': true,
    'input_type': 'number',
    'unit': 'bar',
    'equipment_state': 'stopped',
    'procedure_source': {
      'document_id': 'manual',
      'page': 1,
      'section': 'Pressure test',
    },
  },
};
final _job = <String, dynamic>{
  'id': 'job-a',
  'asset_id': 'asset-a',
  'asset_name': 'Field truck',
  'title': 'Assigned safety check',
  'status': 'assigned',
  'revision': 0,
  'job_type': 'inspection',
  'assigned_to': 'account-a',
  'can_work': true,
  'can_manage': false,
  'checklist_snapshot': [_item],
};
final _service = <String, dynamic>{
  'id': 'service-a',
  'asset_id': 'asset-a',
  'engine_id': 'engine-a',
  'client_id': 'owner-a',
  'title': 'Provider service',
  'status': 'assigned',
  'job_type': 'repair',
  'assigned_to': 'account-a',
  'created_by': 'owner-a',
  'provider_organization_id': 'provider-org',
  'customer_organization_id': 'org-a',
};
final _assignments = [
  {
    'id': 'assignment-a',
    'status': 'pending',
    'checklist_templates': {
      'id': 'retired',
      'name': 'Pinned daily v1',
      'checklist_type': 'operator_daily',
    },
    'assets': {'id': 'asset-a', 'name': 'Field truck'},
  },
];
final _pageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
);

/// Real HTTP and the installed Supabase SDK exercise the production read-through
/// path. Fixture responses are transport inputs, never replacement repositories.
Future<HttpServer> _server(
  List<String> requests, {
  int port = 0,
  bool denied = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.listen((request) async {
    requests.add('${request.method} ${request.uri}');
    request.response.headers.contentType = ContentType.json;
    if (denied) {
      request.response.statusCode = 403;
      request.response.write(
        jsonEncode({
          'code': '42501',
          'message': 'Access denied',
          'details': null,
          'hint': null,
        }),
      );
      await request.response.close();
      return;
    }
    final path = request.uri.path;
    final single =
        request.headers.value('accept')?.contains('object+json') == true;
    dynamic value;
    if (path.endsWith('/profiles')) {
      final profile = {
        'id': 'account-a',
        'email': 'a@example.invalid',
        'full_name': 'Field mechanic',
        'role': 'member',
        'org_id': 'org-a',
      };
      value = single ? profile : [profile];
    } else if (path.endsWith('/organization_context')) {
      value = {
        'active_organization_id': 'org-a',
        'route_role': 'client_mechanic',
        'roles': ['mechanic'],
        'permissions': [],
        'onboarding_required': false,
        'memberships': [
          {
            'organization_id': 'org-a',
            'name': 'Field company',
            'owner_profile_id': 'owner-a',
            'roles': ['mechanic'],
            'permissions': [],
          },
        ],
      };
    } else if (path.endsWith('/client_orgs')) {
      value = {
        'id': 'org-a',
        'name': 'Field company',
        'owner_profile_id': 'owner-a',
        'join_code': 'FIELD12',
      };
    } else if (path.endsWith('/assets')) {
      value = single ? _asset : [_asset];
    } else if (path.endsWith('/asset_workspace')) {
      value = {
        'items': [
          {
            ..._asset,
            'categories': ['inspection_upcoming'],
          },
        ],
      };
    } else if (path.endsWith('/asset_engines')) {
      final engine = {
        'id': 'engine-a',
        'asset_id': 'asset-a',
        'label': 'Primary meter',
        'kind': 'engine',
        'current_hours': 25000,
        'meter_unit': 'km',
      };
      value = single ? engine : [engine];
    } else if (path.endsWith('/asset_custody')) {
      value = [
        {'asset_id': 'asset-a', 'lifecycle': 'active'},
      ];
    } else if (path.endsWith('/client_capabilities')) {
      value = [
        for (final key in [
          'pm_checklists',
          'operational_checklists',
          'maintenance_planning',
        ])
          {'capability_key': key, 'enabled': true},
      ];
    } else if (path.endsWith('/checklist_assignments')) {
      value = _assignments;
    } else if (path.endsWith('/checklist_templates')) {
      value = [
        {
          'id': 'active',
          'name': 'Current daily',
          'checklist_type': 'operator_daily',
          'is_active': true,
        },
        {
          'id': 'retired',
          'name': 'Pinned daily v1',
          'checklist_type': 'operator_daily',
          'is_active': false,
        },
        {
          'id': 'unassigned-retired',
          'name': 'Old unrelated',
          'checklist_type': 'operator_daily',
          'is_active': false,
        },
      ];
    } else if (path.endsWith('/checklist_items')) {
      value = request.uri.queryParameters['template_id'] == 'eq.retired'
          ? [_item]
          : [];
    } else if (path.endsWith('/checklist_source_page')) {
      final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (data['p_template'] != 'retired' || data['p_item'] != 'item-retired') {
        throw StateError('Unexpected source identity');
      }
      value = {
        'title': 'Truck manual',
        'page': 1,
        'object_path': 'manual/1.png',
      };
    } else if (path.contains('/maintenance-documents/')) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(_pageBytes);
      await request.response.close();
      return;
    } else if (path.endsWith('/maintenance_workspace')) {
      value = {
        'assets': [_asset],
      };
    } else if (path.endsWith('/maintenance_jobs')) {
      value = [_job];
    } else if (path.endsWith('/maintenance_asset_context')) {
      value = {
        'asset': _asset,
        'components': [],
        'plans': [],
        'templates': [],
        'assignees': [],
      };
    } else if (path.endsWith('/maintenance_work_hub')) {
      value = {
        'jobs': [_job],
        'plans': [],
      };
    } else if (path.endsWith('/work_orders')) {
      value = single ? _service : [];
    } else if (path.endsWith('/organization_work_orders')) {
      value = [_service];
    } else if (path.endsWith('/work_order_assignments')) {
      value = [
        {
          'id': 'worker-link',
          'work_order_id': 'service-a',
          'profile_id': 'account-a',
        },
      ];
    } else if (path.endsWith('/work_order_checklist_snapshots')) {
      value = {
        'work_order_id': 'service-a',
        'template_id': 'retired',
        'template_version': 1,
        'template_name': 'Pinned daily v1',
        'checklist_type': 'operator_daily',
        'items_json': [_item],
      };
    } else {
      request.response.statusCode = 404;
      value = {
        'code': 'fixture-missing',
        'message': 'Unexpected fixture route $path',
      };
    }
    request.response.write(jsonEncode(value));
    await request.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This integration test uses a local fixture server through the real SDK.
  HttpOverrides.global = null;
  test(
    'real warmed app repositories reopen offline with pinned pages, tasks and drafts; accounts and revocation stay isolated',
    () async {
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      SharedPreferences.setMockInitialValues({});
      final requests = <String>[];
      HttpServer? server = await _server(requests);
      final port = server.port;
      final folder = await Directory.systemTemp.createTemp(
        'next-offline-restart-',
      );
      final file = File('${folder.path}/account-a.sqlite');
      await Supabase.initialize(
        url: 'http://127.0.0.1:$port',
        anonKey: 'fixture-public',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
      );
      final client = Supabase.instance.client;
      await client.auth.recoverSession(jsonEncode(_session('account-a')));
      var db = AppDatabase.forAccount(
        'account-a',
        executor: NativeDatabase(file),
      );
      FieldWorkQueue makeQueue(AppDatabase database, String account) =>
          FieldWorkQueue(
            database,
            account: account,
            currentAccount: () => client.auth.currentUser?.id,
            send: (op) async {
              await client
                  .rpc(op.kind, params: op.payload)
                  .timeout(const Duration(seconds: 2));
            },
          );
      var queue = makeQueue(db, 'account-a');
      ProviderContainer makeContainer(
        AppDatabase database,
        FieldWorkQueue outbox,
      ) => ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          fieldWorkQueueProvider.overrideWithValue(outbox),
          sessionProvider.overrideWithValue(client.auth.currentSession),
        ],
      );
      var container = makeContainer(db, queue);
      try {
        await container.read(profileProvider.future);
        await container
            .read(offlineReadinessProvider.notifier)
            .refresh(force: true)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () =>
                  throw StateError('Warmup timed out:\n${requests.join('\n')}'),
            );
        expect(
          container.read(offlineReadinessProvider).readyAt(DateTime.now()),
          isTrue,
          reason: requests.join('\n'),
        );
        expect(
          requests.any((r) => r.contains('template_id=eq.retired')),
          isTrue,
        );
        expect(
          requests.any((r) => r.contains('template_id=eq.unassigned-retired')),
          isFalse,
        );
        expect(
          requests.any((r) => r.contains('/maintenance-documents/')),
          isTrue,
        );
        final initialWork = await container.read(workListProvider(null).future);
        expect(initialWork.map((row) => row.id).toSet(), {
          'job-a',
          'service-a',
        });
        expect(
          initialWork.singleWhere((row) => row.id == 'service-a').route,
          '/work-orders/service-a',
        );
        final draft = {
          'operation_id': 'run-a',
          'assignment_id': 'assignment-a',
          'assetId': 'asset-a',
          'templateId': 'retired',
          'started_at': '2026-09-12T06:00:00Z',
          'meter_unit': 'km',
          'responses': {'item-retired': 'monitor'},
          'notes': {'item-retired': '6.2'},
          'issues': {
            'item-retired': {
              'message': 'Seal leaks',
              'urgency': 'urgent',
              'safe_to_operate': 'unsafe',
            },
          },
          'photos': {'item-retired': base64Encode(_pageBytes)},
        };
        await OperatorChecklistDraftStore(
          'account-a',
          () => client.auth.currentUser?.id,
        ).save(draft);
        await server.close(force: true);
        server = null;
        await container.read(maintenanceRepositoryProvider).change(
          'job-a',
          0,
          'report-op',
          'save_report',
          {
            'diagnosis': 'Found seal leak',
            'repair': 'Awaiting parts',
            'notes': 'Preserve this draft',
            'answers': {
              'item-retired': {'result': 'fail', 'note': '6.2'},
            },
            'evidence_paths': [],
            'completion_hours': 25001,
          },
        );
        expect((await queue.list()).single.status, 'pending');
        container.dispose();
        queue.close();
        await db.close();
        // The platform store persists between app instances; reset Dart's plugin
        // singleton too, while SQLite is really closed and reopened from disk.
        final prefs = await SharedPreferences.getInstance();
        final persisted = {
          for (final key in prefs.getKeys()) key: prefs.get(key)!,
        };
        SharedPreferences.setMockInitialValues(persisted);
        db = AppDatabase.forAccount(
          'account-a',
          executor: NativeDatabase(file),
        );
        queue = makeQueue(db, 'account-a');
        container = makeContainer(db, queue);
        expect((await container.read(profileProvider.future))!.orgId, 'org-a');
        expect(
          (await container.read(visibleAssetsProvider.future)).single.name,
          'Field truck',
        );
        expect(
          (await container.read(assetWorkspaceProvider.future))['items'],
          isNotEmpty,
        );
        expect(
          (await container.read(
            operatorAssignedAssetsProvider.future,
          )).single['id'],
          'asset-a',
        );
        expect(
          (await container.read(
            myChecklistAssignmentsProvider.future,
          )).single['id'],
          'assignment-a',
        );
        final templates = await container
            .read(checklistRepositoryProvider)
            .listTemplates();
        expect(
          templates.singleWhere((t) => t.id == 'retired').isActive,
          isFalse,
        );
        final items = await container
            .read(checklistRepositoryProvider)
            .listItemsForTemplate('retired');
        expect(items.single.definition['equipment_state'], 'stopped');
        final page = await ChecklistSourceRepository(
          'account-a',
        ).page(items.single.toJson());
        expect(base64Decode(page['bytes'] as String), _pageBytes);
        expect(
          (await workOrderChecklistSnapshotRepository.fetchByWorkOrderId(
            'service-a',
          ))!.templateVersion,
          1,
        );
        final jobs = await container
            .read(maintenanceRepositoryProvider)
            .jobs(jobId: 'job-a');
        expect(jobs.single.report['diagnosis'], 'Found seal leak');
        expect(jobs.single.data['local_pending'], isTrue);
        expect(
          (await container.read(
            maintenancePlanningProvider(null).future,
          )).jobs.map((j) => j.id).toSet(),
          {'job-a', 'service-a'},
        );
        expect(
          (await container.read(
            workListProvider('asset-a').future,
          )).map((j) => j.id).toSet(),
          {'job-a', 'service-a'},
        );
        expect(
          (await OperatorChecklistDraftStore(
            'account-a',
            () => client.auth.currentUser?.id,
          ).list()).single,
          draft,
        );
        await container.read(offlineReadinessProvider.notifier).restore();
        expect(
          container.read(offlineReadinessProvider).readyAt(DateTime.now()),
          isTrue,
        );
        await client.auth.recoverSession(jsonEncode(_session('account-b')));
        final otherDb = AppDatabase.forAccount(
          'account-b',
          executor: NativeDatabase(File('${folder.path}/account-b.sqlite')),
        );
        final other = WorkOrderRepository(
          otherDb,
          client: client,
          organizationMembership: true,
        );
        await expectLater(
          other.listWorkOrders(),
          throwsA(predicate<Object>(isConnectionFailure)),
        );
        expect(
          await OperatorChecklistDraftStore(
            'account-b',
            () => client.auth.currentUser?.id,
          ).list(),
          isEmpty,
        );
        await expectLater(
          container.read(workOrderRepositoryProvider).listWorkOrders(),
          throwsA(isA<AccountChangedException>()),
        );
        await otherDb.close();
        await client.auth.recoverSession(jsonEncode(_session('account-a')));
        server = await _server(requests, port: port, denied: true);
        await expectLater(
          container.read(workOrderRepositoryProvider).listWorkOrders(),
          throwsA(isA<PostgrestException>()),
        );
        expect(
          (await queue.list()).single.status,
          'pending',
          reason: 'Revocation removes prepared reads, never unsent field work',
        );
        expect(
          (await OperatorChecklistDraftStore(
            'account-a',
            () => client.auth.currentUser?.id,
          ).list()).single,
          draft,
        );
        expect(
          (await SharedPreferences.getInstance()).getKeys().where(
            (key) => key.startsWith(accountStorageKey('account-a', 'cache:')),
          ),
          isEmpty,
        );
      } finally {
        container.dispose();
        queue.close();
        await db.close();
        await server?.close(force: true);
        await Supabase.instance.dispose();
        await folder.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
