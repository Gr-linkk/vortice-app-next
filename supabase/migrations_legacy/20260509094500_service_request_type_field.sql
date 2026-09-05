alter table public.service_requests
  add column if not exists request_type text not null default 'other_issue';

update public.service_requests
set request_type = case lower(trim(title))
  when 'breakdown' then 'breakdown'
  when 'service / maintenance' then 'service_maintenance'
  when 'safety concern' then 'safety_concern'
  else request_type
end
where request_type = 'other_issue';

alter table public.service_requests
  drop constraint if exists service_requests_request_type_check;

alter table public.service_requests
  add constraint service_requests_request_type_check
  check (request_type in (
    'breakdown',
    'service_maintenance',
    'safety_concern',
    'other_issue'
  ));

comment on column public.service_requests.request_type is
  'Simple client-selected intake bucket: breakdown, service_maintenance, safety_concern, or other_issue.';
