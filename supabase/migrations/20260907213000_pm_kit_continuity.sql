-- NOW-022: keep editable PM kits connected to company checklist publications.
create function public.can_edit_pm_kit(p_template uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.checklist_templates t where t.id=p_template
 and t.is_active and t.checklist_type='pm' and public.checklist_can_author(t.client_id,'pm'))
$$;
revoke all on function public.can_edit_pm_kit(uuid) from public,anon;
grant execute on function public.can_edit_pm_kit(uuid) to authenticated;
drop policy "Client reads PM parts" on public.pm_parts_requirements;
drop policy "Employee read" on public.pm_parts_requirements;
drop policy "Owner full access" on public.pm_parts_requirements;
create policy pm_kit_read on public.pm_parts_requirements for select to authenticated
 using(public.checklist_template_visible(template_id));
create policy pm_kit_add on public.pm_parts_requirements for insert to authenticated
 with check(public.can_edit_pm_kit(template_id));
create policy pm_kit_edit on public.pm_parts_requirements for update to authenticated
 using(public.can_edit_pm_kit(template_id)) with check(public.can_edit_pm_kit(template_id));
create policy pm_kit_remove on public.pm_parts_requirements for delete to authenticated
 using(public.can_edit_pm_kit(template_id));
alter table public.pm_parts_requirements add constraint pm_kit_valid_requirement
 check(length(btrim(description)) between 1 and 300 and qty>0 and qty<1000000) not valid;

create function public.copy_published_pm_kit()
returns trigger language plpgsql security definer set search_path='' as $$
declare source uuid;
begin
 if new.procedure_id is null or new.checklist_type<>'pm' then return new; end if;
 select coalesce(p.published_template_id,nullif(p.draft->>'source_template_id','')::uuid)
 into source from public.checklist_procedures p where p.id=new.procedure_id;
 if source is not null then
  insert into public.pm_parts_requirements(template_id,description,part_number,qty,unit,notes)
  select new.id,r.description,r.part_number,r.qty,r.unit,r.notes from public.pm_parts_requirements r
  where r.template_id=source and r.qty>0 and r.qty<1000000 and length(btrim(r.description)) between 1 and 300;
 end if;
 return new;
end $$;
revoke all on function public.copy_published_pm_kit() from public,anon;
create trigger copy_published_pm_kit after insert on public.checklist_templates
 for each row execute function public.copy_published_pm_kit();
