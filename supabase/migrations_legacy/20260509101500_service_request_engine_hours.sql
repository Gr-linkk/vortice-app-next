alter table public.service_requests
  add column if not exists engine_hours numeric;

comment on column public.service_requests.engine_hours is
  'Client-supplied current engine/machine hours at service request intake; used to prefill generated work orders.';
