begin;

alter table public.profiles
  add column if not exists subscription_start date,
  add column if not exists paid_until date;

update public.profiles
set subscription_start = created_at::date
where role = 'student' and subscription_start is null;

alter table public.profiles
  add constraint profiles_subscription_period_check
  check (paid_until is null or subscription_start is null or paid_until >= subscription_start);

alter table public.resources
  add column if not exists career text not null default 'Ambos',
  add column if not exists module_name text not null default 'Módulo geral',
  add column if not exists topic_key text,
  add column if not exists position integer not null default 1,
  add column if not exists release_month integer not null default 1;

alter table public.resources
  add constraint resources_career_check check (career in ('CFO','Soldado','Ambos')),
  add constraint resources_module_name_check check (length(trim(module_name)) between 1 and 150),
  add constraint resources_position_check check (position between 1 and 999),
  add constraint resources_release_month_check check (release_month between 1 and 24);

create index if not exists resources_learning_path_idx
  on public.resources(career,subject,module_name,position);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from public.profiles
  where id=(select auth.uid())
    and active
    and (paid_until is null or paid_until >= (now() at time zone 'America/Bahia')::date)
 );
$$;

create or replace function public.is_premium() returns boolean
language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from public.profiles
  where id=(select auth.uid())
    and active
    and (role='admin' or (plan='Estratégico' and (paid_until is null or paid_until >= (now() at time zone 'America/Bahia')::date)))
 );
$$;

create or replace function public.can_access_resource(resource_career text, resource_release_month integer)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
  select 1 from public.profiles p
  where p.id=(select auth.uid())
    and p.active
    and (p.role='admin' or (
      p.plan='Estratégico'
      and (p.paid_until is null or p.paid_until >= (now() at time zone 'America/Bahia')::date)
      and (resource_career='Ambos' or resource_career=p.career)
      and (
        p.paid_until is null
        or resource_release_month <= greatest(1,ceil(((p.paid_until-coalesce(p.subscription_start,p.created_at::date))+1)/30.0)::integer)
      )
    ))
 );
$$;

drop policy if exists resource_read on public.resources;
create policy resource_read on public.resources for select to authenticated
using ((select public.is_admin()) or public.can_access_resource(career,release_month));

grant update(subscription_start,paid_until) on public.profiles to authenticated;
grant insert,update,delete on public.resources to authenticated;

revoke execute on function public.can_access_resource(text,integer) from public,anon;
grant execute on function public.can_access_resource(text,integer) to authenticated;

commit;
