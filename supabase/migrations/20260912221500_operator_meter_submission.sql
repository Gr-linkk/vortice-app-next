-- An offline draft records its meter unit. Do not relabel an old reading if a
-- manager selected the asset's initial primary meter before it was uploaded.
alter function public.submit_operations_checklist(uuid,jsonb) rename to submit_operations_checklist_before_meter_context;
create function public.submit_operations_checklist(p_operation uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare asset public.assets;
begin
 if not coalesce(public.operations_can_submit((p_data->>'asset_id')::uuid),false) then raise exception 'Access denied' using errcode='42501'; end if;
 select * into asset from public.assets where id=(p_data->>'asset_id')::uuid for share;
 if not exists(select 1 from public.operations_submissions where id=p_operation) and p_data ? 'meter_unit'
  and p_data->>'meter_unit' is distinct from asset.meter_unit then
  raise exception 'The equipment meter changed; review this saved reading before submitting' using errcode='40001';
 end if;
 return public.submit_operations_checklist_before_meter_context(p_operation,p_data);
end $$;
revoke all on function public.submit_operations_checklist_before_meter_context(uuid,jsonb),public.submit_operations_checklist(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.submit_operations_checklist(uuid,jsonb) to authenticated;
