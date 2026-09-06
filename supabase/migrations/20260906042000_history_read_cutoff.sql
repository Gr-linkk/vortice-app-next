-- A management API may send multiple SQL commands in one request. Its statement
-- timestamp predates earlier writes within that request. Capture the cutoff at
-- history-function entry so read-after-write includes those already captured rows.
-- Subsequent pages still reuse that exact cutoff and exclude later captures.
create or replace function public.asset_history(p_asset uuid,p_category text default null,p_search text default '',
 p_from timestamptz default null,p_to timestamptz default null,p_before timestamptz default null,
 p_before_id uuid default null,p_limit integer default 50,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; entries jsonb; cutoff timestamptz:=least(coalesce(p_as_of,clock_timestamp()),clock_timestamp());
begin
 if not coalesce(public.maintenance_can_view_asset(p_asset),false) then raise exception 'Access denied' using errcode='42501'; end if;
 if (p_category is not null and p_category not in ('asset','usage','inspection','fault','availability','work','service','parts','discussion'))
  or length(coalesce(p_search,''))>200 or p_limit is null or p_limit not between 1 and 200
  or (p_from is not null and p_to is not null and p_from>=p_to)
  or (p_before is null)<>(p_before_id is null) then raise exception 'Invalid history filter'; end if;
 select jsonb_build_object('asset_id',id,'asset_name',name,'as_of',cutoff) into result from public.assets where id=p_asset;
 select coalesce(jsonb_agg(to_jsonb(e)-'source_key'-'recorded_at' order by e.occurred_at desc,e.id desc),'[]') into entries
 from (select h.* from public.asset_history_entries h where h.asset_id=p_asset
  and h.recorded_at<=cutoff and public.asset_history_readable(h)
  and (p_category is null or h.category=p_category)
  and (p_from is null or h.occurred_at>=p_from) and (p_to is null or h.occurred_at<p_to)
  and (p_before is null or (h.occurred_at,h.id)<(p_before,p_before_id))
  and (btrim(coalesce(p_search,''))='' or position(lower(btrim(p_search)) in lower(h.title||' '||h.body||' '||h.detail::text))>0)
  order by h.occurred_at desc,h.id desc limit p_limit+1) e;
 return result||jsonb_build_object('entries',coalesce((select jsonb_agg(value order by ordinality)
  from jsonb_array_elements(entries) with ordinality where ordinality<=p_limit),'[]'),
  'has_more',jsonb_array_length(entries)>p_limit);
end $$;
