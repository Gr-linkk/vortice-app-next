import json, subprocess, urllib.request, uuid
from pathlib import Path
root=Path.cwd()
def cli(*args):
    return subprocess.run(args,check=True,capture_output=True,text=True).stdout
assert cli('git','remote','get-url','origin').strip()=='https://github.com/Gr-linkk/vortice-app-next.git'
assert (root/'supabase/.temp/project-ref').read_text().strip()=='hkjpojobdbbtjkhaudki'
assets={}
for pattern in ['NOW-010-fixture-*.json','NOW-010-custody-live-*.json']:
    for file in (root/'outputs').glob(pattern):
        item=json.loads(file.read_text(encoding='utf-8-sig'))
        assert item['marker'].startswith('E2E-010')
        if item.get('asset'):
            assets[str(uuid.UUID(item['asset']))]=item.get('asset_name','E2E-010 Custody inspection crane')
assert assets
ids=','.join("'"+a+"'::uuid" for a in sorted(assets))
def query(sql):
    (root/'work/cleanup010-query.sql').write_text(sql)
    return json.loads(cli('supabase','db','query','--linked','--file','work/cleanup010-query.sql','--output','json'))
sql=f"""select jsonb_build_object(
 'assets',(select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.assets where id in ({ids})),
 'work_ids',(select jsonb_agg(id) from public.work_orders where asset_id in ({ids})),
 'request_ids',(select jsonb_agg(id) from public.service_requests where asset_id in ({ids})),
 'objects',(select jsonb_agg(jsonb_build_object('bucket_id',bucket_id,'name',name)) from storage.objects where
  (bucket_id='inspection-evidence' and split_part(name,'/',1)=any(array[{','.join(repr(a) for a in sorted(assets))}])) or
  (bucket_id='service-request-photos' and split_part(name,'/',1) in (select id::text from public.service_requests where asset_id in ({ids})))),
 'unrelated_assets',(select count(*) from public.assets where id not in ({ids})),
 'unrelated_work',(select count(*) from public.work_orders where asset_id not in ({ids})),
 'unrelated_requests',(select count(*) from public.service_requests where asset_id is null or asset_id not in ({ids})),
 'unrelated_inspections',(select count(*) from public.asset_inspections where asset_id not in ({ids})),
 'unrelated_posts',(select count(*) from public.coordination_posts where asset_id not in ({ids})),
 'unrelated_invoices',(select count(*) from public.invoices where work_order_id not in(select id from public.work_orders where asset_id in ({ids})))) as manifest;"""
before=query(sql)[0]['manifest']
for item in before['assets'] or []: assert assets[item['id']]==item['name']
objects=before['objects'] or []
active_assets={item['id'] for item in before['assets'] or []}
for file in (root/'outputs').glob('NOW-010-custody-live-*.json'):
    fixture=json.loads(file.read_text())
    if fixture['asset'] not in active_assets: continue
    for name in fixture['objects']:
        item={'bucket_id':'inspection-evidence','name':name}
        if item not in objects: objects.append(item)
probe_file=root/'outputs/NOW-010-photo-probe-manifest.json'
if probe_file.exists():
    probe=json.loads(probe_file.read_text())
    item={key:probe[key] for key in ['bucket_id','name']}
    if probe['asset'] in active_assets and item not in objects: objects.append(item)
keys=json.loads(cli('supabase','projects','api-keys','--project-ref','hkjpojobdbbtjkhaudki','--output','json'))
key=next(k['api_key'] for k in keys if k['name']=='service_role')
for item in objects:
    assert item['bucket_id'] in ['inspection-evidence','service-request-photos']
    assert item['name'].split('/')[0] in assets or item['name'].split('/')[0] in (before['request_ids'] or [])
    request=urllib.request.Request('https://hkjpojobdbbtjkhaudki.supabase.co/storage/v1/object/'+item['bucket_id'],
      data=json.dumps({'prefixes':[item['name']]}).encode(),method='DELETE',
      headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=30) as response: assert response.status==200
del keys,key
guard=' or '.join("(id='"+a+"'::uuid and name<>"+"'"+name.replace("'","''")+"')" for a,name in assets.items())
jobs=f'select id from public.work_orders where asset_id in ({ids})'
posts=f'select id from public.coordination_posts where asset_id in ({ids})'
cleanup=f"""begin;
do $$ begin
 if exists(select 1 from public.assets where {guard}) then raise exception 'Fixture identity mismatch'; end if;
end $$;
delete from public.coordination_mentions where post_id in ({posts});
delete from public.coordination_acknowledgements where post_id in ({posts});
delete from public.coordination_posts where asset_id in ({ids});
delete from public.invoices where work_order_id in ({jobs});
delete from public.service_requests where asset_id in ({ids});
delete from public.hour_logs where asset_id in ({ids}) or work_order_id in ({jobs});
delete from public.maintenance_requests where asset_id in ({ids});
delete from public.service_reports where work_order_id in ({jobs});
delete from public.maintenance_labour_sessions where work_order_id in ({jobs});
delete from public.maintenance_operations where object_id in ({ids}) or object_id in ({jobs})
 or object_id in(select id from public.asset_engines where asset_id in ({ids}))
 or object_id in(select id from public.asset_service_intervals where asset_id in ({ids}))
 or object_id in(select id from public.asset_inspections where asset_id in ({ids}));
delete from public.maintenance_job_records where id in ({jobs});
delete from public.work_orders where asset_id in ({ids});
delete from public.saved_checklists where asset_id in ({ids});
delete from public.asset_service_intervals where asset_id in ({ids});
delete from public.assets where id in ({ids});
commit;"""
query(cleanup)
after=query(sql)[0]['manifest']
assert not after['assets'] and not after['objects'] and not after['work_ids'] and not after['request_ids']
for name in before:
    if name.startswith('unrelated_'): assert before[name]==after[name],name
(root/'outputs/NOW-010-cleanup.json').write_text(json.dumps({'assets':assets,'removed_objects':objects,'before':before,'after':after},indent=2))
print(f'PASS cleanup: {len(assets)} exact E2E-010 assets, {len(objects)} evidence objects; unrelated counts preserved')
