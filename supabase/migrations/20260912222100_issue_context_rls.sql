-- A policy runs as its caller. Keep arbitrary-user readers private; this public
-- predicate can only answer for the signed-in actor.
create function public.checklist_issue_context_readable(p_post uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.coordination_post_reader(p_post,auth.uid())
$$;
revoke all on function public.checklist_issue_context_readable(uuid) from public,anon;
grant execute on function public.checklist_issue_context_readable(uuid) to authenticated;
alter policy checklist_issue_context_read on public.checklist_issue_context
 using(public.checklist_issue_context_readable(post_id));
