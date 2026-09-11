begin;
alter table public.study_logs add column notes text not null default '';
alter table public.cycles add column start_date date;
create table public.password_requests(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,created_at timestamptz not null default now(),resolved_at timestamptz);
create unique index password_request_pending on public.password_requests(student_id) where resolved_at is null;
alter table public.password_requests enable row level security;
revoke all on public.password_requests from public,anon,authenticated;
grant select on public.password_requests to authenticated;
create policy mentor_requests on public.password_requests for select to authenticated using(public.is_admin());
create table public.question_comments(id uuid primary key default gen_random_uuid(),question_id uuid not null references public.questions(id) on delete cascade,student_id uuid not null references public.profiles(id) on delete cascade,body text not null check(length(trim(body)) between 1 and 5000),created_at timestamptz not null default now());
create index on public.question_comments(question_id,created_at);
create index on public.question_comments(student_id);
alter table public.question_comments enable row level security;
revoke all on public.question_comments from public,anon,authenticated;
grant select,insert,delete on public.question_comments to authenticated;
create policy comments_read on public.question_comments for select to authenticated using(public.is_premium());
create policy comments_insert on public.question_comments for insert to authenticated with check(public.is_premium() and student_id=auth.uid());
create policy comments_delete on public.question_comments for delete to authenticated using(public.is_admin() or (public.is_premium() and student_id=auth.uid()));
create table public.account_rate_limits(key text primary key,window_start timestamptz not null,hits integer not null);
alter table public.account_rate_limits enable row level security;
revoke all on public.account_rate_limits from public,anon,authenticated;
grant all on public.account_rate_limits,public.password_requests to service_role;
create function public.consume_account_limit(bucket text) returns boolean language plpgsql security invoker set search_path='' as $$
declare n integer; begin
 insert into public.account_rate_limits(key,window_start,hits) values(bucket,now(),1)
 on conflict(key) do update set hits=case when account_rate_limits.window_start<now()-interval '15 minutes' then 1 else account_rate_limits.hits+1 end,window_start=case when account_rate_limits.window_start<now()-interval '15 minutes' then now() else account_rate_limits.window_start end returning hits into n;
 delete from public.account_rate_limits where window_start<now()-interval '1 day';
 return n<=5;
end; $$;
revoke all on function public.consume_account_limit(text) from public,anon,authenticated;
grant execute on function public.consume_account_limit(text) to service_role;
-- Deleting an account also deletes only that student's dependent records.
do $$ declare r record; begin
 for r in select conrelid::regclass as tbl,conname,pg_get_constraintdef(oid) as definition from pg_constraint where contype='f' and confrelid='public.profiles'::regclass and confdeltype<>'c' loop
  execute format('alter table %s drop constraint %I',r.tbl,r.conname);
  execute format('alter table %s add constraint %I %s on delete cascade',r.tbl,r.conname,r.definition);
 end loop;
end $$;
alter table private.exam_snapshots drop constraint exam_snapshots_attempt_id_fkey;
alter table private.exam_snapshots add constraint exam_snapshots_attempt_id_fkey foreign key(attempt_id) references public.exam_attempts(id) on delete cascade;
alter table public.exam_attempts drop constraint exam_attempts_exam_id_fkey;
alter table public.exam_attempts add constraint exam_attempts_exam_id_fkey foreign key(exam_id) references public.exams(id) on delete cascade;
grant delete on public.exams to authenticated;
commit;
