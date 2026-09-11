-- Execute once in a NEW Supabase project's SQL Editor, as project owner.
-- No passwords or service-role keys are stored in this application.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null, name text not null,
 role text not null default 'student' check(role in ('student','admin')),
 plan text not null default 'Básico' check(plan in ('Básico','Estratégico')),
 career text not null default 'CFO' check(career in ('CFO','Soldado')),
 active boolean not null default false,
 created_at timestamptz not null default now()
);
create function public.on_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,email,name) values(new.id,new.email,coalesce(nullif(left(new.raw_user_meta_data->>'name',150),''),'Aluno'));
 return new;
end; $$;
create trigger create_student after insert on auth.users for each row execute function public.on_signup();
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active and role='admin'); $$;
create function public.is_member() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active); $$;
create function public.is_premium() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and active and (plan='Estratégico' or role='admin')); $$;

create table public.cycles(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),title text not null,notes text not null default '',blocks jsonb not null default '[]',status text not null check(status in ('Rascunho','Publicado')),created_at timestamptz not null default now(),check(jsonb_typeof(blocks)='array'));
create table public.progress(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),key text not null,flags jsonb not null default '{}',unique(student_id,key),check(jsonb_typeof(flags)='object'));
create table public.study_logs(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),date date not null,subject text not null,topic text not null,source text not null,origin text not null default 'external' check(origin in ('external','platform','exam')),total integer not null check(total>=0 and total<=100000),correct integer not null check(correct>=0 and correct<=total),minutes integer not null default 0 check(minutes>=0 and minutes<=1440),created_at timestamptz not null default now());
create table public.history(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),title text not null,body text not null,visible boolean not null default true,created_at timestamptz not null default now());
create table public.questions(id uuid primary key default gen_random_uuid(),subject text not null,topic text not null,board text not null default '',year integer,difficulty text not null default 'Média',tags text not null default '',body text not null,options jsonb not null,source text not null default '',created_at timestamptz not null default now(),check(jsonb_typeof(options)='array' and jsonb_array_length(options) between 2 and 5));
create table private.question_keys(question_id uuid primary key references public.questions(id) on delete cascade,correct_index integer not null check(correct_index between 0 and 4),explanation text not null);
create table public.question_notes(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),question_id uuid not null references public.questions(id),body text not null default '',highlights jsonb not null default '[]',unique(student_id,question_id),check(jsonb_typeof(highlights)='array'));
create table public.errors(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),subject text not null,topic text not null,reason text not null,source text not null default '',body text not null,explanation text not null default '',reviewed boolean not null default false,created_at timestamptz not null default now());
create table public.resources(id uuid primary key default gen_random_uuid(),title text not null,kind text not null check(kind in ('Material','Vídeo')),subject text not null,description text not null default '',url text,storage_path text,created_at timestamptz not null default now(),check((url is not null and url ~ '^https?://') or storage_path is not null));
create table public.resource_views(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),resource_id uuid not null references public.resources(id),created_at timestamptz not null default now());
create table public.exams(id uuid primary key default gen_random_uuid(),title text not null,description text not null default '',duration integer not null check(duration between 10 and 360),question_ids uuid[] not null,created_at timestamptz not null default now(),check(cardinality(question_ids) between 1 and 500));
create table public.exam_attempts(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id),exam_id uuid not null references public.exams(id),started_at timestamptz not null default now(),deadline timestamptz not null,submitted_at timestamptz,score integer,total integer,details jsonb);
create table private.exam_snapshots(attempt_id uuid primary key references public.exam_attempts(id),questions jsonb not null);
alter table private.question_keys enable row level security;
alter table private.exam_snapshots enable row level security;
create index on public.study_logs(student_id,date);
create index on public.cycles(student_id);
create index on public.history(student_id);
create index on public.errors(student_id);
create index on public.resource_views(student_id);
create index on public.exam_attempts(student_id);

alter table public.profiles enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_admin on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.cycles enable row level security;
create policy cycle_read on public.cycles for select to authenticated using(public.is_admin() or (public.is_member() and student_id=auth.uid() and status='Publicado'));
create policy cycle_admin on public.cycles for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.progress enable row level security;
create policy progress_read on public.progress for select to authenticated using(public.is_admin() or (public.is_member() and student_id=auth.uid()));
create policy progress_insert on public.progress for insert to authenticated with check(public.is_member() and student_id=auth.uid());
create policy progress_update on public.progress for update to authenticated using(public.is_member() and student_id=auth.uid()) with check(public.is_member() and student_id=auth.uid());
alter table public.study_logs enable row level security;
create policy log_read on public.study_logs for select to authenticated using(public.is_admin() or (public.is_member() and student_id=auth.uid()));
create policy log_insert on public.study_logs for insert to authenticated with check(origin='external' and date<=(now() at time zone 'America/Bahia')::date and (public.is_admin() or (public.is_member() and student_id=auth.uid())));
alter table public.history enable row level security;
create policy history_read on public.history for select to authenticated using(public.is_admin() or (public.is_member() and student_id=auth.uid() and visible));
create policy history_admin on public.history for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.questions enable row level security;
create policy question_read on public.questions for select to authenticated using(public.is_premium());
-- Questions are written atomically together with their private answer keys by RPC only.
alter table public.question_notes enable row level security;
create policy own_notes on public.question_notes for all to authenticated using(public.is_premium() and student_id=auth.uid()) with check(public.is_premium() and student_id=auth.uid());
alter table public.errors enable row level security;
create policy error_read on public.errors for select to authenticated using(public.is_admin() or (public.is_premium() and student_id=auth.uid()));
create policy error_insert on public.errors for insert to authenticated with check(public.is_premium() and student_id=auth.uid());
create policy error_update on public.errors for update to authenticated using(public.is_premium() and student_id=auth.uid()) with check(public.is_premium() and student_id=auth.uid());
alter table public.resources enable row level security;
create policy resource_read on public.resources for select to authenticated using(public.is_premium());
create policy resource_admin on public.resources for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.resource_views enable row level security;
create policy view_read on public.resource_views for select to authenticated using(public.is_admin() or(public.is_member() and student_id=auth.uid()));
create policy view_insert on public.resource_views for insert to authenticated with check(public.is_premium() and student_id=auth.uid());
alter table public.exams enable row level security;
create policy exam_read on public.exams for select to authenticated using(public.is_premium());
create policy exam_admin on public.exams for all to authenticated using(public.is_admin()) with check(public.is_admin());
alter table public.exam_attempts enable row level security;
create policy attempt_read on public.exam_attempts for select to authenticated using(public.is_admin() or(public.is_premium() and student_id=auth.uid()));

create function public.save_question(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare qid uuid; opts jsonb; answer integer;
begin
 if not public.is_admin() then raise exception 'Acesso restrito ao administrador'; end if;
 opts:=payload->'options'; answer:=(payload->>'correct_index')::integer;
 if jsonb_typeof(opts) is distinct from 'array' or jsonb_array_length(opts) not between 2 and 5 or answer is null or answer<0 or answer>=jsonb_array_length(opts) then raise exception 'Alternativas ou gabarito inválidos'; end if;
 qid:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());
 insert into public.questions(id,subject,topic,board,year,difficulty,tags,body,options,source)
 values(qid,payload->>'subject',payload->>'topic',coalesce(payload->>'board',''),(payload->>'year')::integer,payload->>'difficulty',coalesce(payload->>'tags',''),payload->>'body',opts,coalesce(payload->>'source',''))
 on conflict(id) do update set subject=excluded.subject,topic=excluded.topic,board=excluded.board,year=excluded.year,difficulty=excluded.difficulty,tags=excluded.tags,body=excluded.body,options=excluded.options,source=excluded.source;
 insert into private.question_keys values(qid,answer,payload->>'explanation') on conflict(question_id) do update set correct_index=excluded.correct_index,explanation=excluded.explanation;
 return qid;
end; $$;
create function public.get_question_key(qid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Acesso restrito ao administrador'; end if;
 return (select jsonb_build_object('correct_index',k.correct_index,'explanation',k.explanation) from private.question_keys k where k.question_id=qid);
end; $$;
create function public.answer_question(qid uuid,selected integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.questions; k private.question_keys; ok boolean;
begin
 if not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico'; end if;
 select * into q from public.questions where id=qid;
 select * into k from private.question_keys where question_id=qid;
 if q.id is null or k.question_id is null or selected is null or selected<0 or selected>=jsonb_array_length(q.options) then raise exception 'Questão ou alternativa inválida'; end if;
 ok:=selected=k.correct_index;
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes) values(auth.uid(),(now() at time zone 'America/Bahia')::date,q.subject,q.topic,'Plataforma','platform',1,case when ok then 1 else 0 end,0);
 return jsonb_build_object('correct',ok,'correct_index',k.correct_index,'explanation',k.explanation);
end; $$;
create function public.start_exam(eid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ex public.exams; a public.exam_attempts; snap jsonb;
begin
 if not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico'; end if;
 select * into ex from public.exams where id=eid;
 if ex.id is null then raise exception 'Simulado não encontrado'; end if;
 select jsonb_agg(jsonb_build_object('id',q.id,'subject',q.subject,'topic',q.topic,'correct_index',k.correct_index,'explanation',k.explanation) order by ord) into snap
 from unnest(ex.question_ids) with ordinality as x(id,ord) join public.questions q on q.id=x.id join private.question_keys k on k.question_id=q.id;
 if snap is null or jsonb_array_length(snap)<>cardinality(ex.question_ids) then raise exception 'Há questões indisponíveis neste simulado'; end if;
 insert into public.exam_attempts(student_id,exam_id,deadline) values(auth.uid(),eid,now()+make_interval(mins=>ex.duration)) returning * into a;
 insert into private.exam_snapshots values(a.id,snap);
 return jsonb_build_object('id',a.id,'deadline',a.deadline);
end; $$;
create function public.submit_exam(attempt_id uuid,responses jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.exam_attempts; snap jsonb; q jsonb; ok boolean; scored integer:=0; results jsonb:='[]'; late boolean;
begin
 if not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico'; end if;
 if jsonb_typeof(responses) is distinct from 'object' then raise exception 'Respostas inválidas'; end if;
 select * into a from public.exam_attempts where id=attempt_id and student_id=auth.uid() for update;
 if a.id is null then raise exception 'Tentativa não encontrada'; end if;
 if a.submitted_at is not null then return jsonb_build_object('score',a.score,'total',a.total,'details',a.details); end if;
 late:=now()>a.deadline+interval '15 seconds';
 if late then raise exception 'Prazo encerrado. Não é possível enviar novas respostas.'; end if;
 select questions into snap from private.exam_snapshots where private.exam_snapshots.attempt_id=a.id;
 for q in select * from jsonb_array_elements(snap) loop
  ok:=coalesce(responses->>(q->>'id'),'')=(q->>'correct_index');
  if ok then scored:=scored+1; end if;
  results:=results||jsonb_build_array(jsonb_build_object('question_id',q->>'id','correct',ok,'correct_index',(q->>'correct_index')::integer,'explanation',q->>'explanation'));
  insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes) values(auth.uid(),(now() at time zone 'America/Bahia')::date,q->>'subject',q->>'topic','Simulado','exam',1,case when ok then 1 else 0 end,0);
 end loop;
 update public.exam_attempts set submitted_at=now(),score=scored,total=jsonb_array_length(snap),details=results where id=a.id;
 return jsonb_build_object('score',scored,'total',jsonb_array_length(snap),'details',results);
end; $$;

-- Explicit least-privilege table grants. RLS is always the authorization boundary.
revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.cycles,public.progress,public.study_logs,public.history,public.questions,public.question_notes,public.errors,public.resources,public.resource_views,public.exams,public.exam_attempts to authenticated;
grant update(name,plan,career,active) on public.profiles to authenticated;
grant insert,update on public.cycles,public.progress,public.history,public.question_notes,public.errors,public.resources,public.exams to authenticated;
grant insert on public.study_logs,public.resource_views to authenticated;
revoke execute on function public.on_signup() from public,anon,authenticated;
revoke execute on function public.is_admin(),public.is_member(),public.is_premium(),public.save_question(jsonb),public.get_question_key(uuid),public.answer_question(uuid,integer),public.start_exam(uuid),public.submit_exam(uuid,jsonb) from public,anon;
grant execute on function public.is_admin(),public.is_member(),public.is_premium(),public.save_question(jsonb),public.get_question_key(uuid),public.answer_question(uuid,integer),public.start_exam(uuid),public.submit_exam(uuid,jsonb) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('materials','materials',false,52428800,array['application/pdf','video/mp4','video/webm','image/png','image/jpeg','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy materials_read on storage.objects for select to authenticated using(bucket_id='materials' and public.is_premium());
create policy materials_upload on storage.objects for insert to authenticated with check(bucket_id='materials' and public.is_admin());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('site-assets','site-assets',true,3145728,array['image/png']);
create policy site_assets_read on storage.objects for select to public using(bucket_id='site-assets');
create policy site_assets_upload on storage.objects for insert to authenticated with check(bucket_id='site-assets' and public.is_admin());
create policy site_assets_update on storage.objects for update to authenticated using(bucket_id='site-assets' and public.is_admin()) with check(bucket_id='site-assets' and public.is_admin());
commit;
