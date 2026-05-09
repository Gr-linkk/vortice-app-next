-- Remove client/customer sign-off language from checklist data.
-- Product rule: checklists must never ask for client sign-off/signature.
-- Keep row IDs because historical checklist_responses may reference them.

update public.checklist_items
set description_en = case
  when description_en ilike '%before launch%' then 'Final operational review before launch'
  else 'Final review'
end
where description_en ilike any (array[
  '%client sign%',
  '%customer sign%',
  '%sign-off%',
  '%sign off%',
  '%signature%'
]);

do $$
begin
  if to_regclass('public.work_order_checklist_snapshots') is not null then
    update public.work_order_checklist_snapshots
    set
      items_json = coalesce((
        select jsonb_agg(
          case
            when coalesce(item->>'description_en', '') ilike '%before launch%'
              then jsonb_set(item, '{description_en}', to_jsonb('Final operational review before launch'::text))
            when coalesce(item->>'description_en', '') ilike any (array[
              '%client sign%',
              '%customer sign%',
              '%sign-off%',
              '%sign off%',
              '%signature%'
            ])
              then jsonb_set(item, '{description_en}', to_jsonb('Final review'::text))
            else item
          end
          order by (item->>'sort_order')::int
        )
        from jsonb_array_elements(items_json::jsonb) as item
      ), '[]'::jsonb),
      updated_at = now()
    where items_json::text ilike any (array[
      '%client sign%',
      '%customer sign%',
      '%sign-off%',
      '%sign off%',
      '%signature%'
    ]);
  end if;
end $$;
