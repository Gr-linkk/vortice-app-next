import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/features/membership/provider_report_draft.dart';

class RefusedAckCleanup extends InMemorySharedPreferencesStore {
  RefusedAckCleanup() : super.empty();
  bool failRemove = true;
  @override
  Future<bool> remove(String key) async => failRemove ? false : super.remove(key);
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Server acknowledgement followed by failed local cleanup reopens an exact frozen retry', () async {
    final disk = RefusedAckCleanup();
    SharedPreferencesStorePlatform.instance = disk;
    final sent = <Map<String,dynamic>>[];
    ProviderReportDraft make() => ProviderReportDraft(account:'audit-account', organizationId:'provider',workOrderId:'job',currentAccount:()=> 'audit-account',send:(command) async { sent.add(command.toJson()); });
    final draft=make();await draft.load();
    final original=<String,dynamic>{'notes':'synthetic original','nested':{'photo':'synthetic-path'}};
    await expectLater(draft.submit(revision:7,action:'submit',data:original),throwsStateError);
    expect(sent,hasLength(1));
    original['notes']='later edit';
    (original['nested'] as Map)['photo']='later photo';
    disk.failRemove=false;
    final reopened=make();await reopened.load();
    await reopened.submit(revision:99,action:'save_report',data:original);
    expect(sent,hasLength(2));
    expect(jsonEncode(sent[1]),jsonEncode(sent[0]));
    expect(sent[1]['revision'],7);expect(sent[1]['action'],'submit');
    expect((await SharedPreferences.getInstance()).getString(reopened.storageKey),isNull);
  });
  test('Populated version7 upgrade preserves pending operation bytes and attachment/report references', () async {
    final root=await Directory.systemTemp.createTemp('vortice-upgrade-audit-');
    final file=File('${root.path}/fixture.sqlite');
    final old=AppDatabase.forAccount('audit-account',executor:NativeDatabase(file));
    await old.customStatement("INSERT INTO work_orders(id,asset_id,client_id,title,created_by,notes_internal) VALUES ('job','asset','client','Synthetic job','creator','private synthetic notes')");
    await old.customStatement("INSERT INTO service_reports(id,work_order_id,correction,sync_status) VALUES ('report','job','synthetic captured correction','pending_create')");
    const payload='{"account":"audit-account","sequence":42,"data":{"operation":"frozen-id","revision":7,"photo":"synthetic-path"}}';
    await old.customStatement("INSERT INTO sync_operations(id,entity_type,entity_remote_id,operation_type,payload_json,status) VALUES ('frozen-id','field_work','job','rpc',?,'pending')",[payload]);
    await old.customStatement("INSERT INTO local_attachments(id,owner_entity_type,owner_local_id,purpose,local_path,sha256) VALUES ('photo','service_report','report','evidence','synthetic-path','synthetic-hash')");
    for (final table in ['assets','asset_engines','work_orders','service_reports']) {
      await old.customStatement('ALTER TABLE $table DROP COLUMN meter_unit');
    }
    await old.customStatement('ALTER TABLE assets DROP COLUMN primary_meter_engine_id');
    await old.customStatement('PRAGMA user_version=7');
    await old.close();
    final upgraded=AppDatabase.forAccount('audit-account',executor:NativeDatabase(file));
    try {
      final command=(await upgraded.customSelect('SELECT id,payload_json,status FROM sync_operations').get()).single;
      expect(command.data,{'id':'frozen-id','payload_json':payload,'status':'pending'});
      final report=(await upgraded.customSelect('SELECT work_order_id,correction,sync_status,meter_unit FROM service_reports').get()).single;
      expect(report.data,{'work_order_id':'job','correction':'synthetic captured correction','sync_status':'pending_create','meter_unit':'hours'});
      final attachment=(await upgraded.customSelect('SELECT owner_local_id,local_path,sha256 FROM local_attachments').get()).single;
      expect(attachment.data,{'owner_local_id':'report','local_path':'synthetic-path','sha256':'synthetic-hash'});
      final job=(await upgraded.customSelect('SELECT created_by,notes_internal,meter_unit FROM work_orders').get()).single;
      expect(job.data,{'created_by':'creator','notes_internal':'private synthetic notes','meter_unit':'hours'});
      expect((await upgraded.customSelect('PRAGMA user_version').get()).single.data.values.single,8);
    } finally { await upgraded.close();await root.delete(recursive:true); }
  });
}
