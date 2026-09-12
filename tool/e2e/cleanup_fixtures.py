import argparse, json, os, subprocess, urllib.request, uuid
from datetime import datetime, timezone
from pathlib import Path

parser=argparse.ArgumentParser(description='Remove exact connected-test fixtures from one explicit run directory.')
parser.add_argument('--manifest-dir', type=Path, default=os.environ.get('VORTICE_E2E_OUTPUT'),
    help='Run output directory; defaults only to VORTICE_E2E_OUTPUT, never all historical outputs.')
parser.add_argument('--receipt', type=Path, help='New cleanup receipt path; must not already exist.')
parser.add_argument('--connection-root', type=Path,
    help='Optional verified Next checkout whose existing CLI linkage should be reused.')
args=parser.parse_args()
if args.manifest_dir is None:
    parser.error('Specify --manifest-dir or VORTICE_E2E_OUTPUT (use --manifest-dir outputs explicitly for legacy manifests).')
manifest_dir=args.manifest_dir.resolve()
if not manifest_dir.is_dir():
    parser.error('Manifest directory must already exist.')
receipt=(args.receipt or manifest_dir/f"cleanup-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}.json").resolve()
if receipt.exists():
    parser.error('Receipt already exists; choose a new path to preserve prior evidence.')
root=Path.cwd().resolve()
connection_root=(args.connection_root or root).resolve()

def cli(*args, cwd=root):
    return subprocess.run(args,cwd=cwd,check=True,capture_output=True,text=True).stdout

def verify_repository(directory):
    assert Path(cli('git','rev-parse','--show-toplevel',cwd=directory).strip()).resolve()==directory
    assert cli('git','remote',cwd=directory).split()==['origin']
    assert cli('git','remote','get-url','origin',cwd=directory).strip()=='https://github.com/Gr-linkk/vortice-app-next.git'
    assert (directory/'supabase/.temp/project-ref').read_text().strip()=='hkjpojobdbbtjkhaudki'

verify_repository(root)
verify_repository(connection_root)
assets={}
stocks={}
builder_markers=set()
for pattern in ['NOW-010-fixture-*.json','NOW-010-custody-live-*.json','NOW-011-fixture-*.json','NOW-012-fixture-*.json','NOW-013-fixture-*.json','NOW-014-fixture-*.json','NOW-015-fixture-*.json','NOW-022-fixture-*.json']:
    for file in manifest_dir.glob(pattern):
        assert file.resolve().parent==manifest_dir, 'Manifest must belong to the selected run directory'
        item=json.loads(file.read_text(encoding='utf-8-sig'))
        assert item['marker'].startswith(('E2E-010','E2E-011','E2E-012','E2E-013','E2E-014','E2E-015','E2E-022'))
        for stock in item.get('stocks',[]):
            assert stock['description'].startswith(item['marker']+' ')
            stocks[str(uuid.UUID(stock['id']))]=stock['description']
        if item['marker'].startswith(('E2E-015-','E2E-022-')):
            marker=item['marker']
            assert len(marker)==16 and all(c in '0123456789abcdef' for c in marker[8:])
            builder_markers.add(marker)
        if item.get('asset'):
            assets[str(uuid.UUID(item['asset']))]=item.get('asset_name','E2E-010 Custody inspection crane')
assert assets
query_file=manifest_dir/f'cleanup-query-{uuid.uuid4().hex}.sql'
ids=','.join("'"+a+"'::uuid" for a in sorted(assets))
stock_ids=','.join("'"+a+"'::uuid" for a in sorted(stocks)) or 'select null::uuid where false'
def query(sql):
    query_file.write_text(sql,encoding='utf-8')
    return json.loads(cli('supabase','db','query','--linked','--file',str(query_file),'--output','json',cwd=connection_root))
marker_values=','.join(repr(m) for m in sorted(builder_markers)) or "''"
procedures=query(f"select p.id,p.draft->>'name' as name,u.email from public.checklist_procedures p join public.profiles u on u.id=p.created_by where split_part(p.draft->>'name',' ',1) in ({marker_values})")
for item in procedures:
    assert item['name'].split(' ')[0] in builder_markers
    assert item['email'] in ('owner@vortice.dev','paradise@vortice.dev')
procedure_ids=','.join("'"+str(uuid.UUID(p['id']))+"'::uuid" for p in procedures) or 'select null::uuid where false'
templates=f'select id from public.checklist_templates where procedure_id in ({procedure_ids})'
sql=f"""select jsonb_build_object(
 'unrelated_stock',(select count(*) from public.parts_inventory where id not in ({stock_ids})),
 'assets',(select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.assets where id in ({ids})),
 'work_ids',(select jsonb_agg(id) from public.work_orders where asset_id in ({ids})),
 'request_ids',(select jsonb_agg(id) from public.service_requests where asset_id in ({ids})),
 'objects',(select jsonb_agg(jsonb_build_object('bucket_id',bucket_id,'name',name)) from storage.objects where
  (bucket_id in ('inspection-evidence','operator-evidence') and split_part(name,'/',1)=any(array[{','.join(repr(a) for a in sorted(assets))}])) or
  (bucket_id='maintenance-evidence' and split_part(name,'/',1) in (select id::text from public.work_orders where asset_id in ({ids}))) or
  (bucket_id='service-report-photos' and split_part(name,'/',1)='checklists' and
   (split_part(name,'/',2) in (select id::text from public.work_orders where asset_id in ({ids})) or
    split_part(name,'/',2) in (select 'asset_'||id::text from public.assets where id in ({ids})))) or
  (bucket_id='service-request-photos' and split_part(name,'/',1) in (select id::text from public.service_requests where asset_id in ({ids})))),
 'unrelated_assets',(select count(*) from public.assets where id not in ({ids})),
 'unrelated_operator_runs',(select count(*) from public.operator_checklist_runs where asset_id not in ({ids})),
 'unrelated_operator_submissions',(select count(*) from public.operations_submissions where asset_id not in ({ids})),
 'unrelated_work',(select count(*) from public.work_orders where asset_id is null or asset_id not in ({ids})),
 'unrelated_requests',(select count(*) from public.service_requests where asset_id is null or asset_id not in ({ids})),
 'unrelated_templates',(select count(*) from public.checklist_templates where procedure_id is null or procedure_id not in ({procedure_ids})),
 'unrelated_procedures',(select count(*) from public.checklist_procedures where id not in ({procedure_ids})),
 'unrelated_assignments',(select count(*) from public.checklist_assignments where asset_id is null or asset_id not in ({ids})),
 'unrelated_inspections',(select count(*) from public.asset_inspections where asset_id not in ({ids})),
 'unrelated_posts',(select count(*) from public.coordination_posts where asset_id not in ({ids})),
 'unrelated_invoices',(select count(*) from public.invoices where work_order_id not in(select id from public.work_orders where asset_id in ({ids})))) as manifest;"""
before=query(sql)[0]['manifest']
for item in before['assets'] or []: assert assets[item['id']]==item['name']
objects=before['objects'] or []
active_assets={item['id'] for item in before['assets'] or []}
for file in manifest_dir.glob('NOW-010-custody-live-*.json'):
    fixture=json.loads(file.read_text(encoding='utf-8-sig'))
    if fixture['asset'] not in active_assets: continue
    for name in fixture['objects']:
        item={'bucket_id':'inspection-evidence','name':name}
        if item not in objects: objects.append(item)
probe_file=manifest_dir/'NOW-010-photo-probe-manifest.json'
if probe_file.exists():
    assert probe_file.resolve().parent==manifest_dir, 'Probe must belong to the selected run directory'
    probe=json.loads(probe_file.read_text(encoding='utf-8-sig'))
    item={key:probe[key] for key in ['bucket_id','name']}
    if probe['asset'] in active_assets and item not in objects: objects.append(item)
# Reject references outside the fixture before deleting any media.
query(f"""do $$ begin
 if exists(select 1 from public.work_orders where checklist_template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.saved_checklists where template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.checklist_assignments where template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.asset_service_intervals where checklist_template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.checklist_procedures where id not in ({procedure_ids}) and draft->>'source_template_id' in (select id::text from public.checklist_templates where procedure_id in ({procedure_ids})))
 then raise exception 'Fixture checklist is referenced outside the test'; end if;
end $$;""")
receipt.parent.mkdir(parents=True,exist_ok=True)
with receipt.open('x',encoding='utf-8') as output:
    json.dump({'status':'started','manifest_dir':str(manifest_dir),'assets':assets,'procedures':procedures,'objects':objects,'before':before},output,indent=2)
keys=json.loads(cli('supabase','projects','api-keys','--project-ref','hkjpojobdbbtjkhaudki','--output','json'))
key=next(k['api_key'] for k in keys if k['name']=='service_role')
for item in objects:
    assert item['bucket_id'] in ['inspection-evidence','service-request-photos','operator-evidence','maintenance-evidence','service-report-photos']
    if item['bucket_id']=='service-report-photos':
        parts=item['name'].split('/')
        assert parts[0]=='checklists' and (parts[1] in (before['work_ids'] or []) or parts[1] in ['asset_'+a for a in assets])
    else:
        assert item['name'].split('/')[0] in assets or item['name'].split('/')[0] in (before['request_ids'] or []) or item['name'].split('/')[0] in (before['work_ids'] or [])
    request=urllib.request.Request('https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/'+item['bucket_id'],
      data=json.dumps({'prefixes':[item['name']]}).encode(),method='DELETE',
      headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=30) as response: assert response.status==200
del keys,key
guard=' or '.join("(id='"+a+"'::uuid and name<>"+"'"+name.replace("'","''")+"')" for a,name in assets.items())
stock_guard=' or '.join("(id='"+a+"'::uuid and description<>"+"'"+name.replace("'","''")+"')" for a,name in stocks.items()) or 'false'
jobs=f'select id from public.work_orders where asset_id in ({ids})'
posts=f'select id from public.coordination_posts where asset_id in ({ids})'
cleanup=f"""begin;
do $$ begin
 if exists(select 1 from public.assets where {guard}) then raise exception 'Fixture identity mismatch'; end if;
 if exists(select 1 from public.parts_inventory where {stock_guard})
  or exists(select 1 from public.job_part_requirements where stock_id in ({stock_ids}) and work_order_id not in ({jobs}))
  or exists(select 1 from public.parts_stock_events where stock_id in ({stock_ids}) and work_order_id not in ({jobs}))
 then raise exception 'Fixture stock identity or reference mismatch'; end if;
 if exists(select 1 from public.work_orders where checklist_template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.saved_checklists where template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.checklist_assignments where template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.asset_service_intervals where checklist_template_id in ({templates}) and (asset_id is null or asset_id not in ({ids})))
  or exists(select 1 from public.checklist_procedures where id not in ({procedure_ids}) and draft->>'source_template_id' in (select id::text from public.checklist_templates where procedure_id in ({procedure_ids})))
 then raise exception 'Fixture checklist is referenced outside the test'; end if;
end $$;
delete from public.notifications where asset_id in ({ids});
delete from public.checklist_findings where run_id in(select id from public.operator_checklist_runs where asset_id in ({ids}));
delete from public.maintenance_operations where object_id in(select id from public.checklist_assignments where asset_id in ({ids}));
update public.operator_checklist_runs set assignment_id=null where asset_id in ({ids});
delete from public.checklist_assignments where asset_id in ({ids});
delete from public.operator_checklist_responses where run_id in(select id from public.operator_checklist_runs where asset_id in ({ids}));
delete from public.operator_checklist_runs where asset_id in ({ids});
delete from public.operations_submissions where asset_id in ({ids});
delete from public.coordination_mentions where post_id in ({posts});
delete from public.coordination_acknowledgements where post_id in ({posts});
delete from public.coordination_posts where asset_id in ({ids});
-- Issued financial history is immutable in normal application use. This
-- privileged fixture-only transaction restores its guard before committing.
alter table public.invoices disable trigger invoice_closeout;
delete from public.invoices where work_order_id in ({jobs});
alter table public.invoices enable trigger invoice_closeout;
delete from public.closeout_operations where
 (kind='meter' and payload->>'asset' in (select id::text from public.assets where id in ({ids})))
 or (kind='provider_save' and result in ({jobs}))
 or (kind='request_submission' and result in (select id from public.service_requests where asset_id in ({ids})))
 or (kind='report_submission' and result in (select id from public.service_reports where work_order_id in ({jobs})));
delete from public.service_requests where asset_id in ({ids});
delete from public.hour_logs where asset_id in ({ids}) or work_order_id in ({jobs});
delete from public.maintenance_requests where asset_id in ({ids});
select set_config('app.parts_stock_write','on',true);
delete from public.parts where work_order_id in ({jobs});
delete from public.parts_purchase_requests where requirement_id in(select id from public.job_part_requirements where work_order_id in ({jobs}));
delete from public.parts_stock_events where work_order_id in ({jobs});
delete from public.job_part_requirements where work_order_id in ({jobs});
delete from public.parts_inventory where id in ({stock_ids});
delete from public.service_reports where work_order_id in ({jobs});
delete from public.maintenance_labour_sessions where work_order_id in ({jobs});
delete from public.maintenance_operations where object_id in ({ids}) or object_id in ({jobs})
 or object_id in(select id from public.asset_engines where asset_id in ({ids}))
 or object_id in(select id from public.asset_service_intervals where asset_id in ({ids}))
 or object_id in(select id from public.asset_inspections where asset_id in ({ids}));
delete from public.maintenance_job_records where id in ({jobs});
delete from public.checklist_responses where work_order_id in ({jobs});
delete from public.work_order_sources where work_order_id in ({jobs});
delete from public.work_orders where asset_id in ({ids});
delete from public.saved_checklists where asset_id in ({ids});
delete from public.asset_service_intervals where asset_id in ({ids});
delete from public.checklist_builder_operations where procedure_id in ({procedure_ids});
update public.checklist_procedures set published_template_id=null where id in ({procedure_ids});
delete from public.checklist_items where template_id in ({templates});
delete from public.checklist_templates where procedure_id in ({procedure_ids});
delete from public.checklist_procedures where id in ({procedure_ids});
delete from public.assets where id in ({ids});
commit;"""
query(cleanup)
after=query(sql)[0]['manifest']
assert not after['assets'] and not after['objects'] and not after['work_ids'] and not after['request_ids']
for name in before:
    if name.startswith('unrelated_'): assert before[name]==after[name],name
with receipt.open('w',encoding='utf-8') as output:
    json.dump({'status':'complete','manifest_dir':str(manifest_dir),'assets':assets,'procedures':procedures,'removed_objects':objects,'before':before,'after':after},output,indent=2)
query_file.unlink()
print(f'PASS cleanup: {len(active_assets)} exact E2E-010/011/012/013/014/015 assets, {len(procedures)} fixture procedures, {len(objects)} evidence objects; unrelated counts preserved')

print(f'Receipt: {receipt}')
