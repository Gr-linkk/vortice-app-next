-- A retired attached version stays frozen with the work. Booking/notes edits
-- must not require replacing it with a newer active template.
do $$ declare body text; old text; replacement text; begin
 body:=pg_get_functiondef('public.change_organization_work(uuid,integer,uuid,text,jsonb)'::regprocedure);
 old:='if template is not null and not public.organization_work_template_allowed(w.id,template) then';
 replacement:='if template is not null and template is distinct from w.checklist_template_id and not public.organization_work_template_allowed(w.id,template) then';
 if position(old in body)=0 then raise exception 'Provider configuration contract changed'; end if;
 execute replace(body,old,replacement);
end $$;
