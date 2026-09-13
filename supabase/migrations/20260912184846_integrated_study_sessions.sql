begin;
-- The syllabus key is shared by plans, cards, logs and the student's history.
create table public.syllabus_topics(key text primary key,career text not null,subject text not null,code text not null,title text not null);
alter table public.syllabus_topics enable row level security;
revoke all on public.syllabus_topics from public,anon,authenticated;
grant select on public.syllabus_topics to authenticated;
create policy syllabus_read on public.syllabus_topics for select to authenticated using((select public.is_member()));
create table public.study_sessions(
 id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,
 cycle_id uuid not null references public.cycles(id) on delete cascade,block_id text not null,topic_key text not null,
 subject text not null,topic text not null,plan_day integer not null,
 target_seconds integer not null check(target_seconds between 60 and 57600),focus_seconds integer not null check(focus_seconds between 60 and 7200),break_seconds integer not null check(break_seconds between 0 and 1800),
 focused_seconds numeric not null default 0,phase_seconds numeric not null default 0,phase text not null default 'focus' check(phase in ('focus','break')),
 status text not null default 'paused' check(status in ('paused','running','ended')),started_at timestamptz not null default now(),heartbeat_at timestamptz not null default now(),ended_at timestamptz
);
create unique index one_open_study_session on public.study_sessions(student_id) where status<>'ended';
create index study_sessions_cycle_idx on public.study_sessions(cycle_id);
create table public.cycle_days(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,cycle_id uuid not null references public.cycles(id) on delete cascade,day integer not null,started_at timestamptz not null default now(),completed_at timestamptz,advanced_at timestamptz,unique(cycle_id,day));
create index cycle_days_student_idx on public.cycle_days(student_id);
create table public.flashcards(id uuid primary key default gen_random_uuid(),topic_key text not null references public.syllabus_topics(key),front text not null check(length(trim(front)) between 1 and 5000),back text not null check(length(trim(back)) between 1 and 10000),review_keys text[] not null default array['r3','r4'],created_at timestamptz not null default now());
create index flashcards_topic_idx on public.flashcards(topic_key);
create table public.flashcard_runs(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,cycle_id uuid not null references public.cycles(id) on delete cascade,study_id uuid not null references public.method_studies(id) on delete cascade,review_id uuid references public.method_reviews(id) on delete cascade,step_id text,topic_key text not null,plan_day integer not null,cards jsonb not null,answers jsonb not null default '{}',started_at timestamptz not null default now(),completed_at timestamptz,check((review_id is not null)<>(step_id is not null)));
create unique index flash_run_review on public.flashcard_runs(review_id) where review_id is not null;
create unique index flash_run_step on public.flashcard_runs(study_id,step_id) where step_id is not null;
create index flash_run_student_idx on public.flashcard_runs(student_id);
create index flash_run_cycle_idx on public.flashcard_runs(cycle_id);
create table public.topic_events(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,topic_key text not null,kind text not null,created_at timestamptz not null default now());
create index topic_events_student_topic_idx on public.topic_events(student_id,topic_key,created_at);
alter table public.study_logs alter column minutes type numeric(10,2);
alter table public.study_logs add column session_id uuid unique references public.study_sessions(id) on delete set null,add column cycle_id uuid references public.cycles(id) on delete set null,add column plan_day integer,add column topic_key text,add column error_reason text;
create index study_logs_topic_idx on public.study_logs(student_id,topic_key);
create index study_logs_cycle_idx on public.study_logs(cycle_id);
alter table public.study_logs drop constraint study_logs_origin_check;
alter table public.study_logs add constraint study_logs_origin_check check(origin in ('external','platform','exam','method','timer'));
alter table public.errors add column log_id uuid unique references public.study_logs(id) on delete set null;
alter table public.exams add column career text check(career in ('CFO','Soldado'));
-- Existing unclassified exams remain intact and visible to the mentor for classification.
drop policy exam_read on public.exams;
create policy exam_read on public.exams for select to authenticated using((select public.is_admin()) or ((select public.is_premium()) and career=(select career from public.profiles where id=(select auth.uid()))));

create function private.plan_position(cid uuid,uid uuid) returns integer language sql stable set search_path='' as $$select coalesce((select (flags->>'day')::integer from public.progress where student_id=uid and key=cid::text||'|position'),1);$$;
create function private.topic_studied(uid uuid,tkey text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.progress where student_id=uid and key='edital|'||tkey and flags->>'study'='true') or exists(select 1 from public.method_studies where student_id=uid and topic_key=tkey and studied_at is not null);$$;
create function private.can_read_cards(tkey text) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and (public.is_admin() or (public.is_premium() and private.topic_studied(auth.uid(),tkey) and exists(select 1 from public.cycles where student_id=auth.uid() and status='Publicado' and private.plan_position(id,auth.uid())>=8)));$$;
create function private.flash_required(c public.cycles,b jsonb,st jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select st->>'kind'='flashcard' and (b->>'date')::date-coalesce(c.start_date,(select min((x->>'date')::date) from jsonb_array_elements(c.blocks)x))+1>=8
 and exists(select 1 from public.profiles p where p.id=c.student_id and (p.plan='Estratégico' or p.role='admin'))
 and (coalesce((b->'method'->>'studied_before')::boolean,false) or exists(select 1 from public.method_studies s where s.student_id=c.student_id and s.topic_key=b->>'topic_key' and s.studied_at is not null and (s.cycle_id<>c.id or s.studied_day<private.plan_position(c.id,c.student_id))))
 and exists(select 1 from public.flashcards f where f.topic_key=b->>'topic_key');
$$;
create function private.review_flash_required(r public.method_reviews) returns boolean language sql stable security definer set search_path='' as $$
 select r.status<>'cancelled' and r.due_day>=8 and exists(select 1 from public.profiles p where p.id=r.student_id and (p.plan='Estratégico' or p.role='admin')) and exists(select 1 from public.method_studies s join public.flashcards f on f.topic_key=s.topic_key where s.id=r.study_id and s.studied_at is not null and r.review_key=any(f.review_keys));
$$;

DO $$ declare t text;begin
 foreach t in array array['study_sessions','cycle_days','flashcard_runs','topic_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy owner_read on public.%I for select to authenticated using ((select public.is_admin()) or ((select public.is_member()) and student_id=(select auth.uid())))',t);
 end loop;
end;$$;
alter table public.flashcards enable row level security;
revoke all on public.flashcards from public,anon,authenticated;
grant select,insert,update,delete on public.flashcards to authenticated;
create policy flashcards_read on public.flashcards for select to authenticated using(private.can_read_cards(topic_key));
create policy flashcards_admin on public.flashcards for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));

create function private.day_summary(cid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles;d integer;b jsonb;s public.method_studies;st jsonb;r public.method_reviews;total_n integer:=0;done_n integer:=0;topics_n integer:=0;block_done boolean;begin
 select * into c from public.cycles where id=cid;
 if c.id is null or auth.uid() is null or not public.is_member() or (c.student_id<>auth.uid() and not public.is_admin()) then raise exception 'Ciclo não encontrado';end if;
 d:=private.plan_position(cid,c.student_id);
 for b in select * from jsonb_array_elements(c.blocks) loop
 if (b->>'date')::date-coalesce(c.start_date,(select min((x->>'date')::date) from jsonb_array_elements(c.blocks)x))+1>d then continue;end if;
 select * into s from public.method_studies where cycle_id=cid and block_id=b->>'id';block_done:=true;
 for st in select * from jsonb_array_elements(private.method_config(b->'method')->'steps') loop
 if st->>'kind'='flashcard' and not private.flash_required(c,b,st) then continue;end if;
 if (b->>'date')::date-c.start_date+1<d and coalesce((s.flags->>(st->>'id'))::boolean,false) then continue;end if;
 total_n:=total_n+1;
 if coalesce((s.flags->>(st->>'id'))::boolean,false) then done_n:=done_n+1;else block_done:=false;end if;
 end loop;
 if block_done and (b->>'date')::date-c.start_date+1=d then topics_n:=topics_n+1;end if;
 end loop;
 for r in select * from public.method_reviews where cycle_id=cid and due_day<=d and status<>'cancelled' loop
 if r.due_day=d or r.status<>'completed' then total_n:=total_n+1;if r.status='completed' then done_n:=done_n+1;end if;end if;
 if private.review_flash_required(r) and (r.due_day=d or not exists(select 1 from public.flashcard_runs where review_id=r.id and completed_at is not null)) then total_n:=total_n+1;if exists(select 1 from public.flashcard_runs where review_id=r.id and completed_at is not null) then done_n:=done_n+1;end if;end if;
 end loop;
 return jsonb_build_object('day',d,'total',total_n,'done',done_n,'complete',total_n=done_n,'subjects_completed',topics_n,'minutes',coalesce((select sum(minutes) from public.study_logs where cycle_id=cid and plan_day=d),0),'questions',coalesce((select sum(total) from public.study_logs where cycle_id=cid and plan_day=d),0));
end;$$;
create function private.touch_study_day(cid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb;c public.cycles;begin
 v:=private.day_summary(cid);select * into c from public.cycles where id=cid;
 insert into public.cycle_days(student_id,cycle_id,day,completed_at) values(c.student_id,cid,(v->>'day')::integer,case when (v->>'complete')::boolean then now() end)
 on conflict(cycle_id,day) do update set completed_at=case when (v->>'complete')::boolean then coalesce(cycle_days.completed_at,now()) else null end;
 return v;
end;$$;
create function public.get_study_day(cycle_uuid uuid) returns jsonb language sql security invoker set search_path='' as $$select private.touch_study_day(cycle_uuid);$$;

create function private.study_timer(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles;s public.study_sessions;b jsonb;d integer;act text:=payload->>'action';delta numeric;phase_limit numeric;stale boolean;begin
 if auth.uid() is null or not public.is_member() then raise exception 'Acesso não liberado';end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 if act='create' then
 select * into c from public.cycles where id=(payload->>'cycle_id')::uuid and student_id=auth.uid() and status='Publicado' for update;
 if c.id is null then raise exception 'Ciclo não encontrado';end if;
 select x into b from jsonb_array_elements(c.blocks)x where x->>'id'=payload->>'block_id';
 d:=private.plan_position(c.id,auth.uid());
 if b is null or (b->>'date')::date-c.start_date+1>d then raise exception 'Assunto indisponível neste dia';end if;
 select * into s from public.study_sessions where student_id=auth.uid() and status<>'ended';
 if s.id is not null then
 if s.cycle_id=c.id and s.block_id=b->>'id' then return to_jsonb(s);end if;
 raise exception 'Encerre a sessão em andamento antes de estudar outro assunto';end if;
 if coalesce((payload->>'minutes')::integer,0) not between 1 and 960 or coalesce((payload->>'focus')::integer,0) not between 1 and 120 or coalesce((payload->>'rest')::integer,-1) not between 0 and 30 then raise exception 'Confira a duração, o foco e o descanso';end if;
 insert into public.study_sessions(student_id,cycle_id,block_id,topic_key,subject,topic,plan_day,target_seconds,focus_seconds,break_seconds) values(auth.uid(),c.id,b->>'id',b->>'topic_key',b->>'subject',b->>'topic',d,(payload->>'minutes')::integer*60,(payload->>'focus')::integer*60,(payload->>'rest')::integer*60) returning * into s;
 perform private.touch_study_day(c.id);
 return to_jsonb(s);
 end if;
 select * into s from public.study_sessions where id=(payload->>'session_id')::uuid and student_id=auth.uid() for update;
 if s.id is null then raise exception 'Sessão não encontrada';end if;
 if act not in ('tick','pause','resume','end') then raise exception 'Comando inválido';end if;
 if s.status='ended' then return to_jsonb(s);end if;
 stale:=now()-s.heartbeat_at>interval '30 seconds';
 if s.status='running' then
 phase_limit:=case when s.phase='focus' then least(s.focus_seconds,s.target_seconds-s.focused_seconds+s.phase_seconds) else s.break_seconds end;
 delta:=greatest(0,least(extract(epoch from now()-s.heartbeat_at),30,phase_limit-s.phase_seconds));
 s.phase_seconds:=s.phase_seconds+delta;
 if s.phase='focus' then s.focused_seconds:=least(s.target_seconds,s.focused_seconds+delta);end if;
 if s.focused_seconds>=s.target_seconds then s.status:='ended';s.ended_at:=now();
 elsif s.phase_seconds>=phase_limit then s.phase:=case when s.phase='focus' and s.break_seconds>0 then 'break' else 'focus' end;s.phase_seconds:=0;s.status:='paused';
 elsif stale then s.status:='paused';end if;
 end if;
 if act='pause' and s.status<>'ended' then s.status:='paused';end if;
 if act='resume' and s.status<>'ended' then s.status:='running';end if;
 if act='end' then s.status:='ended';s.ended_at:=now();end if;
 update public.study_sessions set status=s.status,phase=s.phase,phase_seconds=s.phase_seconds,focused_seconds=s.focused_seconds,heartbeat_at=now(),ended_at=s.ended_at where id=s.id returning * into s;
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes,session_id,cycle_id,plan_day,topic_key) values(auth.uid(),(s.started_at at time zone 'America/Bahia')::date,s.subject,s.topic,'Pomodoro','timer',0,0,round(s.focused_seconds/60,2),s.id,s.cycle_id,s.plan_day,s.topic_key) on conflict(session_id) do update set minutes=excluded.minutes;
 return to_jsonb(s);
end;$$;
create function public.study_timer(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.study_timer(payload);$$;
insert into public.syllabus_topics(key,career,subject,code,title) values
('Soldado|LÍNGUA PORTUGUESA|1.0','Soldado','LÍNGUA PORTUGUESA','1.0','Compreensão e interpretação de textos.'),
('Soldado|LÍNGUA PORTUGUESA|2.0','Soldado','LÍNGUA PORTUGUESA','2.0','Tipologia textual e gêneros textuais.'),
('Soldado|LÍNGUA PORTUGUESA|3.0','Soldado','LÍNGUA PORTUGUESA','3.0','Ortografia oficial.'),
('Soldado|LÍNGUA PORTUGUESA|4.0','Soldado','LÍNGUA PORTUGUESA','4.0','Acentuação gráfica.'),
('Soldado|LÍNGUA PORTUGUESA|5.0','Soldado','LÍNGUA PORTUGUESA','5.0','Classes de palavras.'),
('Soldado|LÍNGUA PORTUGUESA|5.1','Soldado','LÍNGUA PORTUGUESA','5.1','Substantivo, adjetivo e artigo.'),
('Soldado|LÍNGUA PORTUGUESA|5.2','Soldado','LÍNGUA PORTUGUESA','5.2','Pronome: emprego e colocação.'),
('Soldado|LÍNGUA PORTUGUESA|5.3','Soldado','LÍNGUA PORTUGUESA','5.3','Verbo: conjugação, tempos e modos verbais.'),
('Soldado|LÍNGUA PORTUGUESA|5.4','Soldado','LÍNGUA PORTUGUESA','5.4','Advérbio, preposição, conjunção e interjeição.'),
('Soldado|LÍNGUA PORTUGUESA|6.0','Soldado','LÍNGUA PORTUGUESA','6.0','Uso do sinal indicativo de crase.'),
('Soldado|LÍNGUA PORTUGUESA|7.0','Soldado','LÍNGUA PORTUGUESA','7.0','Sintaxe da oração e do período.'),
('Soldado|LÍNGUA PORTUGUESA|7.1','Soldado','LÍNGUA PORTUGUESA','7.1','Termos essenciais, integrantes e acessórios da oração.'),
('Soldado|LÍNGUA PORTUGUESA|7.2','Soldado','LÍNGUA PORTUGUESA','7.2','Coordenação e subordinação entre orações.'),
('Soldado|LÍNGUA PORTUGUESA|8.0','Soldado','LÍNGUA PORTUGUESA','8.0','Pontuação.'),
('Soldado|LÍNGUA PORTUGUESA|9.0','Soldado','LÍNGUA PORTUGUESA','9.0','Concordância nominal e verbal.'),
('Soldado|LÍNGUA PORTUGUESA|9.1','Soldado','LÍNGUA PORTUGUESA','9.1','Concordância nominal.'),
('Soldado|LÍNGUA PORTUGUESA|9.2','Soldado','LÍNGUA PORTUGUESA','9.2','Concordância verbal.'),
('Soldado|LÍNGUA PORTUGUESA|10.0','Soldado','LÍNGUA PORTUGUESA','10.0','Regência nominal e verbal.'),
('Soldado|LÍNGUA PORTUGUESA|10.1','Soldado','LÍNGUA PORTUGUESA','10.1','Regência nominal.'),
('Soldado|LÍNGUA PORTUGUESA|10.2','Soldado','LÍNGUA PORTUGUESA','10.2','Regência verbal.'),
('Soldado|LÍNGUA PORTUGUESA|11.0','Soldado','LÍNGUA PORTUGUESA','11.0','Significação das palavras (sinonímia, antonímia, polissemia).'),
('Soldado|HISTÓRIA DO BRASIL|1.0','Soldado','HISTÓRIA DO BRASIL','1.0','Descobrimento do Brasil (1500).'),
('Soldado|HISTÓRIA DO BRASIL|2.0','Soldado','HISTÓRIA DO BRASIL','2.0','Brasil Colônia (1530–1815).'),
('Soldado|HISTÓRIA DO BRASIL|2.1','Soldado','HISTÓRIA DO BRASIL','2.1','Capitanias Hereditárias e organização político-administrativa.'),
('Soldado|HISTÓRIA DO BRASIL|2.2','Soldado','HISTÓRIA DO BRASIL','2.2','Economia colonial: extrativismo vegetal e mineral, pecuária.'),
('Soldado|HISTÓRIA DO BRASIL|2.3','Soldado','HISTÓRIA DO BRASIL','2.3','Escravidão.'),
('Soldado|HISTÓRIA DO BRASIL|2.4','Soldado','HISTÓRIA DO BRASIL','2.4','Expansão territorial.'),
('Soldado|HISTÓRIA DO BRASIL|3.0','Soldado','HISTÓRIA DO BRASIL','3.0','Independência do Brasil (1822).'),
('Soldado|HISTÓRIA DO BRASIL|3.1','Soldado','HISTÓRIA DO BRASIL','3.1','Nomeação do Príncipe Regente D. Pedro I.'),
('Soldado|HISTÓRIA DO BRASIL|3.2','Soldado','HISTÓRIA DO BRASIL','3.2','Dia do Fico.'),
('Soldado|HISTÓRIA DO BRASIL|3.3','Soldado','HISTÓRIA DO BRASIL','3.3','Reconhecimento da Independência do Brasil.'),
('Soldado|HISTÓRIA DO BRASIL|4.0','Soldado','HISTÓRIA DO BRASIL','4.0','Primeiro Reinado (1822-1831).'),
('Soldado|HISTÓRIA DO BRASIL|5.0','Soldado','HISTÓRIA DO BRASIL','5.0','Segundo Reinado.'),
('Soldado|HISTÓRIA DO BRASIL|6.0','Soldado','HISTÓRIA DO BRASIL','6.0','Primeira República (1889-1930).'),
('Soldado|HISTÓRIA DO BRASIL|6.1','Soldado','HISTÓRIA DO BRASIL','6.1','Primeiro Governo Provisório e Assembleia Constituinte.'),
('Soldado|HISTÓRIA DO BRASIL|6.2','Soldado','HISTÓRIA DO BRASIL','6.2','Presidência de Deodoro da Fonseca.'),
('Soldado|HISTÓRIA DO BRASIL|6.3','Soldado','HISTÓRIA DO BRASIL','6.3','Política dos Governadores e Coronelismo.'),
('Soldado|HISTÓRIA DO BRASIL|6.4','Soldado','HISTÓRIA DO BRASIL','6.4','Movimentos Tenentistas e Coluna Prestes.'),
('Soldado|HISTÓRIA DO BRASIL|6.5','Soldado','HISTÓRIA DO BRASIL','6.5','Revolta da Armada.'),
('Soldado|HISTÓRIA DO BRASIL|7.0','Soldado','HISTÓRIA DO BRASIL','7.0','Revolução de 1930.'),
('Soldado|HISTÓRIA DO BRASIL|8.0','Soldado','HISTÓRIA DO BRASIL','8.0','Era Vargas (1930-1945).'),
('Soldado|HISTÓRIA DO BRASIL|9.0','Soldado','HISTÓRIA DO BRASIL','9.0','Os Presidentes do Brasil de 1964 à atualidade.'),
('Soldado|HISTÓRIA DO BRASIL|10.0','Soldado','HISTÓRIA DO BRASIL','10.0','História da Bahia.'),
('Soldado|HISTÓRIA DO BRASIL|11.0','Soldado','HISTÓRIA DO BRASIL','11.0','Independência da Bahia.'),
('Soldado|HISTÓRIA DO BRASIL|12.0','Soldado','HISTÓRIA DO BRASIL','12.0','Revolta de Canudos.'),
('Soldado|HISTÓRIA DO BRASIL|13.0','Soldado','HISTÓRIA DO BRASIL','13.0','Revolta dos Malês.'),
('Soldado|HISTÓRIA DO BRASIL|14.0','Soldado','HISTÓRIA DO BRASIL','14.0','Conjuração Baiana.'),
('Soldado|HISTÓRIA DO BRASIL|15.0','Soldado','HISTÓRIA DO BRASIL','15.0','Sabinada.'),
('Soldado|GEOGRAFIA DO BRASIL|1.0','Soldado','GEOGRAFIA DO BRASIL','1.0','Relevo brasileiro.'),
('Soldado|GEOGRAFIA DO BRASIL|2.0','Soldado','GEOGRAFIA DO BRASIL','2.0','Urbanização.'),
('Soldado|GEOGRAFIA DO BRASIL|2.1','Soldado','GEOGRAFIA DO BRASIL','2.1','Crescimento urbano e problemas estruturais.'),
('Soldado|GEOGRAFIA DO BRASIL|2.2','Soldado','GEOGRAFIA DO BRASIL','2.2','Contingente populacional brasileiro.'),
('Soldado|GEOGRAFIA DO BRASIL|3.0','Soldado','GEOGRAFIA DO BRASIL','3.0','Matriz energética brasileira.'),
('Soldado|GEOGRAFIA DO BRASIL|3.1','Soldado','GEOGRAFIA DO BRASIL','3.1','Fontes: eólica, hidráulica, biomassa, solar e das marés.'),
('Soldado|GEOGRAFIA DO BRASIL|4.0','Soldado','GEOGRAFIA DO BRASIL','4.0','Problemas ambientais.'),
('Soldado|GEOGRAFIA DO BRASIL|5.0','Soldado','GEOGRAFIA DO BRASIL','5.0','Clima.'),
('Soldado|GEOGRAFIA DO BRASIL|5.1','Soldado','GEOGRAFIA DO BRASIL','5.1','Pressão atmosférica, umidade e temperatura.'),
('Soldado|GEOGRAFIA DO BRASIL|5.2','Soldado','GEOGRAFIA DO BRASIL','5.2','Fatores que determinam o clima.'),
('Soldado|GEOGRAFIA DO BRASIL|5.3','Soldado','GEOGRAFIA DO BRASIL','5.3','Mudanças climáticas e suas consequências.'),
('Soldado|GEOGRAFIA DO BRASIL|6.0','Soldado','GEOGRAFIA DO BRASIL','6.0','Geografia da Bahia.'),
('Soldado|GEOGRAFIA DO BRASIL|6.1','Soldado','GEOGRAFIA DO BRASIL','6.1','Aspectos físicos.'),
('Soldado|GEOGRAFIA DO BRASIL|6.2','Soldado','GEOGRAFIA DO BRASIL','6.2','Aspectos políticos e econômicos.'),
('Soldado|GEOGRAFIA DO BRASIL|6.3','Soldado','GEOGRAFIA DO BRASIL','6.3','Aspectos sociais e culturais.'),
('Soldado|MATEMÁTICA|1.0','Soldado','MATEMÁTICA','1.0','Conjuntos numéricos.'),
('Soldado|MATEMÁTICA|1.1','Soldado','MATEMÁTICA','1.1','Naturais, Inteiros, Racionais, Reais e Complexos.'),
('Soldado|MATEMÁTICA|1.2','Soldado','MATEMÁTICA','1.2','Operações, propriedades e aplicações.'),
('Soldado|MATEMÁTICA|1.3','Soldado','MATEMÁTICA','1.3','Sequências numéricas: progressão aritmética e geométrica.'),
('Soldado|MATEMÁTICA|2.0','Soldado','MATEMÁTICA','2.0','Álgebra.'),
('Soldado|MATEMÁTICA|2.1','Soldado','MATEMÁTICA','2.1','Expressões algébricas.'),
('Soldado|MATEMÁTICA|2.2','Soldado','MATEMÁTICA','2.2','Polinômios: operações e propriedades.'),
('Soldado|MATEMÁTICA|2.3','Soldado','MATEMÁTICA','2.3','Equações polinomiais e inequações relacionadas.'),
('Soldado|MATEMÁTICA|3.0','Soldado','MATEMÁTICA','3.0','Funções.'),
('Soldado|MATEMÁTICA|3.1','Soldado','MATEMÁTICA','3.1','Função do 1º e 2º grau.'),
('Soldado|MATEMÁTICA|3.2','Soldado','MATEMÁTICA','3.2','Função modular.'),
('Soldado|MATEMÁTICA|3.3','Soldado','MATEMÁTICA','3.3','Função exponencial e logarítmica.'),
('Soldado|MATEMÁTICA|3.4','Soldado','MATEMÁTICA','3.4','Gráficos e propriedades.'),
('Soldado|MATEMÁTICA|4.0','Soldado','MATEMÁTICA','4.0','Sistemas lineares, matrizes e determinantes.'),
('Soldado|MATEMÁTICA|5.0','Soldado','MATEMÁTICA','5.0','Análise combinatória e probabilidade.'),
('Soldado|MATEMÁTICA|5.1','Soldado','MATEMÁTICA','5.1','Arranjos, permutações e combinações simples.'),
('Soldado|MATEMÁTICA|5.2','Soldado','MATEMÁTICA','5.2','Binômio de Newton.'),
('Soldado|MATEMÁTICA|5.3','Soldado','MATEMÁTICA','5.3','Probabilidade em espaços amostrais finitos.'),
('Soldado|MATEMÁTICA|6.0','Soldado','MATEMÁTICA','6.0','Geometria e medidas.'),
('Soldado|MATEMÁTICA|6.1','Soldado','MATEMÁTICA','6.1','Geometria plana: figuras, congruência, semelhança, perímetro e área.'),
('Soldado|MATEMÁTICA|6.2','Soldado','MATEMÁTICA','6.2','Geometria espacial: paralelismo, perpendicularismo, áreas e volumes dos sólidos.'),
('Soldado|MATEMÁTICA|6.3','Soldado','MATEMÁTICA','6.3','Geometria analítica no plano: retas, circunferência e distâncias.'),
('Soldado|MATEMÁTICA|7.0','Soldado','MATEMÁTICA','7.0','Trigonometria.'),
('Soldado|MATEMÁTICA|7.1','Soldado','MATEMÁTICA','7.1','Razões e funções trigonométricas.'),
('Soldado|MATEMÁTICA|7.2','Soldado','MATEMÁTICA','7.2','Fórmulas de transformação, equações e triângulos.'),
('Soldado|ATUALIDADES|1.0','Soldado','ATUALIDADES','1.0',' Globalização: conceitos, efeitos e implicações sociais, econômicas, políticas e culturais.'),
('Soldado|ATUALIDADES|2.0','Soldado','ATUALIDADES','2.0','Multiculturalidade, pluralidade e diversidade cultural.'),
('Soldado|ATUALIDADES|3.0','Soldado','ATUALIDADES','3.0','Tecnologias de Informação e Comunicação: conceitos, efeitos e implicações.'),
('Soldado|INFORMÁTICA|1.0','Soldado','INFORMÁTICA','1.0',' Editores de texto, planilhas e apresentações (Word/Writer, Excel/Calc, PowerPoint/Impress).'),
('Soldado|INFORMÁTICA|2.0','Soldado','INFORMÁTICA','2.0','Sistemas operacionais Windows 7, Windows 10 e Linux.'),
('Soldado|INFORMÁTICA|3.0','Soldado','INFORMÁTICA','3.0','Organização e gerenciamento de informações, arquivos, pastas e programas.'),
('Soldado|INFORMÁTICA|4.0','Soldado','INFORMÁTICA','4.0','Atalhos de teclado, ícones, área de trabalho e lixeira.'),
('Soldado|INFORMÁTICA|5.0','Soldado','INFORMÁTICA','5.0','Conceitos básicos de Internet e intranet.'),
('Soldado|INFORMÁTICA|6.0','Soldado','INFORMÁTICA','6.0','Correio eletrônico.'),
('Soldado|INFORMÁTICA|7.0','Soldado','INFORMÁTICA','7.0','Computação em nuvem.'),
('Soldado|DIREITO CONSTITUCIONAL|1.0','Soldado','DIREITO CONSTITUCIONAL','1.0','Constituição da República Federativa do Brasil.'),
('Soldado|DIREITO CONSTITUCIONAL|1.1','Soldado','DIREITO CONSTITUCIONAL','1.1','Princípios fundamentais.'),
('Soldado|DIREITO CONSTITUCIONAL|1.2','Soldado','DIREITO CONSTITUCIONAL','1.2','Direitos e garantias fundamentais.'),
('Soldado|DIREITO CONSTITUCIONAL|1.3','Soldado','DIREITO CONSTITUCIONAL','1.3','Organização do Estado.'),
('Soldado|DIREITO CONSTITUCIONAL|1.4','Soldado','DIREITO CONSTITUCIONAL','1.4','Administração Pública.'),
('Soldado|DIREITO CONSTITUCIONAL|1.5','Soldado','DIREITO CONSTITUCIONAL','1.5','Militares dos Estados, do Distrito Federal e dos Territórios.'),
('Soldado|DIREITO CONSTITUCIONAL|1.6','Soldado','DIREITO CONSTITUCIONAL','1.6','Segurança Pública.'),
('Soldado|DIREITO CONSTITUCIONAL|2.0','Soldado','DIREITO CONSTITUCIONAL','2.0','Constituição do Estado da Bahia.'),
('Soldado|DIREITO CONSTITUCIONAL|2.1','Soldado','DIREITO CONSTITUCIONAL','2.1','Princípios fundamentais.'),
('Soldado|DIREITO CONSTITUCIONAL|2.2','Soldado','DIREITO CONSTITUCIONAL','2.2','Direitos e garantias fundamentais.'),
('Soldado|DIREITO CONSTITUCIONAL|2.3','Soldado','DIREITO CONSTITUCIONAL','2.3','Servidores Públicos Militares.'),
('Soldado|DIREITO CONSTITUCIONAL|2.4','Soldado','DIREITO CONSTITUCIONAL','2.4','Segurança Pública.'),
('Soldado|DIREITOS HUMANOS|1.0','Soldado','DIREITOS HUMANOS','1.0','Declaração Universal dos Direitos Humanos (1948).'),
('Soldado|DIREITOS HUMANOS|2.0','Soldado','DIREITOS HUMANOS','2.0',' Convenção Americana sobre Direitos Humanos/1969 – Pacto de São José da Costa Rica (art. 1º ao 32).'),
('Soldado|DIREITOS HUMANOS|3.0','Soldado','DIREITOS HUMANOS','3.0','Pacto Internacional dos Direitos Econômicos, Sociais e Culturais (art. 1º ao 15).'),
('Soldado|DIREITOS HUMANOS|4.0','Soldado','DIREITOS HUMANOS','4.0','Declaração de Pequim – Quarta Conferência Mundial sobre as Mulheres.'),
('Soldado|DIREITO ADMINISTRATIVO|1.0','Soldado','DIREITO ADMINISTRATIVO','1.0','Administração Pública.'),
('Soldado|DIREITO ADMINISTRATIVO|2.0','Soldado','DIREITO ADMINISTRATIVO','2.0','Princípios fundamentais da Administração Pública.'),
('Soldado|DIREITO ADMINISTRATIVO|3.0','Soldado','DIREITO ADMINISTRATIVO','3.0','Poderes e deveres dos administradores públicos.'),
('Soldado|DIREITO ADMINISTRATIVO|3.1','Soldado','DIREITO ADMINISTRATIVO','3.1','Uso e abuso do poder.'),
('Soldado|DIREITO ADMINISTRATIVO|3.2','Soldado','DIREITO ADMINISTRATIVO','3.2','Poder vinculado, discricionário, hierárquico, disciplinar e regulamentar.'),
('Soldado|DIREITO ADMINISTRATIVO|3.3','Soldado','DIREITO ADMINISTRATIVO','3.3','Poder de polícia.'),
('Soldado|DIREITO ADMINISTRATIVO|3.4','Soldado','DIREITO ADMINISTRATIVO','3.4','Deveres dos administradores públicos.'),
('Soldado|DIREITO ADMINISTRATIVO|4.0','Soldado','DIREITO ADMINISTRATIVO','4.0','Servidores públicos: cargo, emprego e função pública.'),
('Soldado|DIREITO ADMINISTRATIVO|5.0','Soldado','DIREITO ADMINISTRATIVO','5.0','Regime jurídico do militar estadual.'),
('Soldado|DIREITO ADMINISTRATIVO|5.1','Soldado','DIREITO ADMINISTRATIVO','5.1','Estatuto dos Policiais Militares da Bahia – Lei nº 7.990/2001 (arts. 1º ao 59).'),
('Soldado|DIREITO PENAL|1.0','Soldado','DIREITO PENAL','1.0','Do crime.'),
('Soldado|DIREITO PENAL|1.1','Soldado','DIREITO PENAL','1.1','Elementos, consumação e tentativa.'),
('Soldado|DIREITO PENAL|1.2','Soldado','DIREITO PENAL','1.2','Desistência voluntária e arrependimento eficaz.'),
('Soldado|DIREITO PENAL|1.3','Soldado','DIREITO PENAL','1.3','Arrependimento posterior.'),
('Soldado|DIREITO PENAL|1.4','Soldado','DIREITO PENAL','1.4','Crime impossível.'),
('Soldado|DIREITO PENAL|1.5','Soldado','DIREITO PENAL','1.5','Causas de exclusão de ilicitude e culpabilidade.'),
('Soldado|DIREITO PENAL|2.0','Soldado','DIREITO PENAL','2.0','Contravenção penal.'),
('Soldado|DIREITO PENAL|3.0','Soldado','DIREITO PENAL','3.0','Crimes contra a vida.'),
('Soldado|DIREITO PENAL|3.1','Soldado','DIREITO PENAL','3.1','Homicídio.'),
('Soldado|DIREITO PENAL|3.2','Soldado','DIREITO PENAL','3.2','Lesão corporal.'),
('Soldado|DIREITO PENAL|3.3','Soldado','DIREITO PENAL','3.3','Rixa.'),
('Soldado|DIREITO PENAL|4.0','Soldado','DIREITO PENAL','4.0','Crimes contra a liberdade pessoal.'),
('Soldado|DIREITO PENAL|4.1','Soldado','DIREITO PENAL','4.1','Constrangimento ilegal e ameaça.'),
('Soldado|DIREITO PENAL|4.2','Soldado','DIREITO PENAL','4.2','Perseguição.'),
('Soldado|DIREITO PENAL|4.3','Soldado','DIREITO PENAL','4.3','Sequestro e cárcere privado.'),
('Soldado|DIREITO PENAL|5.0','Soldado','DIREITO PENAL','5.0','Crimes contra o patrimônio.'),
('Soldado|DIREITO PENAL|5.1','Soldado','DIREITO PENAL','5.1','Furto e roubo.'),
('Soldado|DIREITO PENAL|5.2','Soldado','DIREITO PENAL','5.2','Extorsão.'),
('Soldado|DIREITO PENAL|5.3','Soldado','DIREITO PENAL','5.3','Apropriação indébita e receptação.'),
('Soldado|DIREITO PENAL|6.0','Soldado','DIREITO PENAL','6.0','Crimes contra a dignidade sexual.'),
('Soldado|DIREITO PENAL|6.1','Soldado','DIREITO PENAL','6.1','Estupro.'),
('Soldado|DIREITO PENAL|6.2','Soldado','DIREITO PENAL','6.2','Importunação sexual e assédio sexual.'),
('Soldado|DIREITO PENAL|7.0','Soldado','DIREITO PENAL','7.0','Corrupção ativa e corrupção passiva.'),
('Soldado|DIREITO PENAL|8.0','Soldado','DIREITO PENAL','8.0','Lei nº 9.455/1997 – Crimes de tortura.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|1.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','1.0','Constituição da República Federativa do Brasil (arts. 1º, 3º, 4º e 5º).'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|2.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','2.0','Constituição do Estado da Bahia – Cap. XXIII "Do Negro".'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|3.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','3.0','Lei nº 12.288/2010 – Estatuto da Igualdade Racial.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|4.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','4.0','Lei nº 7.716/1989 e Lei nº 9.455/1997 – crimes de preconceito de raça ou cor.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|5.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','5.0',' Decreto nº 65.810/1969 – Convenção Internacional sobre Eliminação da Discriminação Racial.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|6.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','6.0',' Decreto nº 4.377/2002 – Convenção sobre Eliminação da Discriminação contra a Mulher.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|7.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','7.0','Lei nº 11.340/2006 – Lei Maria da Penha.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|8.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','8.0','Código Penal Brasileiro (art. 140).'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|9.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','9.0','Lei nº 9.455/1997 – Crime de Tortura.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|10.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','10.0','Lei nº 7.437/1985 – Lei Caó.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|11.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','11.0','Lei estadual nº 10.549/2006 – Secretaria de Promoção da Igualdade Racial.'),
('Soldado|IGUALDADE RACIAL E DE GÊNERO|12.0','Soldado','IGUALDADE RACIAL E DE GÊNERO','12.0','Lei nº 10.678/2003 – Secretaria de Políticas de Promoção da Igualdade Racial.'),
('Soldado|DIREITO PENAL MILITAR|1.0','Soldado','DIREITO PENAL MILITAR','1.0','Crimes contra a autoridade ou disciplina militar.'),
('Soldado|DIREITO PENAL MILITAR|1.1','Soldado','DIREITO PENAL MILITAR','1.1','Motim e revolta.'),
('Soldado|DIREITO PENAL MILITAR|1.2','Soldado','DIREITO PENAL MILITAR','1.2','Conspiração e aliciação para motim ou revolta.'),
('Soldado|DIREITO PENAL MILITAR|2.0','Soldado','DIREITO PENAL MILITAR','2.0','Violência contra superior ou militar de serviço.'),
('Soldado|DIREITO PENAL MILITAR|3.0','Soldado','DIREITO PENAL MILITAR','3.0','Desrespeito a superior.'),
('Soldado|DIREITO PENAL MILITAR|4.0','Soldado','DIREITO PENAL MILITAR','4.0','Recusa de obediência.'),
('Soldado|DIREITO PENAL MILITAR|5.0','Soldado','DIREITO PENAL MILITAR','5.0','Reunião ilícita.'),
('Soldado|DIREITO PENAL MILITAR|6.0','Soldado','DIREITO PENAL MILITAR','6.0','Publicação ou crítica indevida.'),
('Soldado|DIREITO PENAL MILITAR|7.0','Soldado','DIREITO PENAL MILITAR','7.0','Resistência mediante ameaça ou violência.'),
('Soldado|DIREITO PENAL MILITAR|8.0','Soldado','DIREITO PENAL MILITAR','8.0','Crimes contra o serviço e o dever militar.'),
('Soldado|DIREITO PENAL MILITAR|8.1','Soldado','DIREITO PENAL MILITAR','8.1','Deserção e abandono de posto.'),
('Soldado|DIREITO PENAL MILITAR|8.2','Soldado','DIREITO PENAL MILITAR','8.2','Descumprimento de missão.'),
('Soldado|DIREITO PENAL MILITAR|8.3','Soldado','DIREITO PENAL MILITAR','8.3','Embriaguez em serviço e dormir em serviço.'),
('Soldado|DIREITO PENAL MILITAR|9.0','Soldado','DIREITO PENAL MILITAR','9.0','Crimes contra a Administração Militar.'),
('Soldado|DIREITO PENAL MILITAR|9.1','Soldado','DIREITO PENAL MILITAR','9.1','Desacato a superior e desacato a militar.'),
('Soldado|DIREITO PENAL MILITAR|9.2','Soldado','DIREITO PENAL MILITAR','9.2','Desobediência.'),
('Soldado|DIREITO PENAL MILITAR|9.3','Soldado','DIREITO PENAL MILITAR','9.3','Peculato, peculato-furto e concussão.'),
('Soldado|DIREITO PENAL MILITAR|10.0','Soldado','DIREITO PENAL MILITAR','10.0','Crimes contra o dever funcional: prevaricação.'),
('CFO|LÍNGUA PORTUGUESA|1.0','CFO','LÍNGUA PORTUGUESA','1.0','Leitura e interpretação de textos.'),
('CFO|LÍNGUA PORTUGUESA|1.1','CFO','LÍNGUA PORTUGUESA','1.1','Textos verbais extraídos de livros e periódicos contemporâneos.'),
('CFO|LÍNGUA PORTUGUESA|1.2','CFO','LÍNGUA PORTUGUESA','1.2','Textos mistos (verbais/não verbais) e não verbais.'),
('CFO|LÍNGUA PORTUGUESA|1.3','CFO','LÍNGUA PORTUGUESA','1.3','Textos publicitários (propagandas, mensagens publicitárias, outdoors etc.).'),
('CFO|LÍNGUA PORTUGUESA|2.0','CFO','LÍNGUA PORTUGUESA','2.0','Nomes e verbo. Flexões nominais e verbais.'),
('CFO|LÍNGUA PORTUGUESA|3.0','CFO','LÍNGUA PORTUGUESA','3.0','Advérbio e suas circunstâncias (tempo, lugar, meio, intensidade, negação, afirmação, dúvida etc.).'),
('CFO|LÍNGUA PORTUGUESA|4.0','CFO','LÍNGUA PORTUGUESA','4.0','Palavras de relação intervocabular e interoracional: preposições e conjunções.'),
('CFO|LÍNGUA PORTUGUESA|5.0','CFO','LÍNGUA PORTUGUESA','5.0','Frase, oração, período.'),
('CFO|LÍNGUA PORTUGUESA|5.1','CFO','LÍNGUA PORTUGUESA','5.1','Elementos constituintes da oração: termos essenciais, integrantes e acessórios.'),
('CFO|LÍNGUA PORTUGUESA|5.2','CFO','LÍNGUA PORTUGUESA','5.2','Coordenação e subordinação.'),
('CFO|LÍNGUA PORTUGUESA|6.0','CFO','LÍNGUA PORTUGUESA','6.0','Sintaxe de colocação, concordância e regência. Crase.'),
('CFO|LÍNGUA PORTUGUESA|7.0','CFO','LÍNGUA PORTUGUESA','7.0','Formas de discurso: direto, indireto e indireto livre.'),
('CFO|LÍNGUA PORTUGUESA|8.0','CFO','LÍNGUA PORTUGUESA','8.0','Semântica: sinonímia, antonímia e heteronímia.'),
('CFO|LÍNGUA PORTUGUESA|9.0','CFO','LÍNGUA PORTUGUESA','9.0','Pontuação e seus recursos sintático-semânticos.'),
('CFO|LÍNGUA PORTUGUESA|10.0','CFO','LÍNGUA PORTUGUESA','10.0','Acentuação e ortografia.'),
('CFO|LÍNGUA PORTUGUESA|11.0','CFO','LÍNGUA PORTUGUESA','11.0','Diferença entre redação técnica (oficial) e redação estilística e suas características.'),
('CFO|LÍNGUA PORTUGUESA|12.0','CFO','LÍNGUA PORTUGUESA','12.0','Correspondência oficial: conceito e tipos de documentos.'),
('CFO|LÍNGUA PORTUGUESA|13.0','CFO','LÍNGUA PORTUGUESA','13.0','Diferença entre ofício e memorando.'),
('CFO|LÍNGUA INGLESA|1.0','CFO','LÍNGUA INGLESA','1.0','Compreensão de textos verbais e não verbais.'),
('CFO|LÍNGUA INGLESA|2.0','CFO','LÍNGUA INGLESA','2.0','Substantivos: formação do plural (regular, irregular e casos especiais).'),
('CFO|LÍNGUA INGLESA|3.0','CFO','LÍNGUA INGLESA','3.0','Gênero. Contáveis e não contáveis.'),
('CFO|LÍNGUA INGLESA|4.0','CFO','LÍNGUA INGLESA','4.0','Formas possessivas dos nomes. Modificadores do nome.'),
('CFO|LÍNGUA INGLESA|5.0','CFO','LÍNGUA INGLESA','5.0','Artigos e demonstrativos: definidos, indefinidos e outros determinantes.'),
('CFO|LÍNGUA INGLESA|6.0','CFO','LÍNGUA INGLESA','6.0','Adjetivos: grau comparativo e superlativo (regulares e irregulares); indefinidos.'),
('CFO|LÍNGUA INGLESA|7.0','CFO','LÍNGUA INGLESA','7.0','Numerais cardinais e ordinais.'),
('CFO|LÍNGUA INGLESA|8.0','CFO','LÍNGUA INGLESA','8.0','Pronomes pessoais: sujeito e objeto.'),
('CFO|LÍNGUA INGLESA|9.0','CFO','LÍNGUA INGLESA','9.0','Possessivos, reflexivos, indefinidos, interrogativos e relativos.'),
('CFO|LÍNGUA INGLESA|10.0','CFO','LÍNGUA INGLESA','10.0','Verbos: modos, tempos e formas.'),
('CFO|LÍNGUA INGLESA|10.1','CFO','LÍNGUA INGLESA','10.1','Regulares e irregulares; auxiliares e impessoais; modais.'),
('CFO|LÍNGUA INGLESA|10.2','CFO','LÍNGUA INGLESA','10.2','Two-word verbs; voz ativa e voz passiva; o gerúndio e seu uso específico.'),
('CFO|LÍNGUA INGLESA|11.0','CFO','LÍNGUA INGLESA','11.0','Discurso direto e indireto. Sentenças condicionais.'),
('CFO|LÍNGUA INGLESA|12.0','CFO','LÍNGUA INGLESA','12.0','Advérbios: tipos (frequência, modo, lugar, tempo, intensidade, dúvida, afirmação).'),
('CFO|LÍNGUA INGLESA|13.0','CFO','LÍNGUA INGLESA','13.0','Expressões adverbiais.'),
('CFO|LÍNGUA INGLESA|14.0','CFO','LÍNGUA INGLESA','14.0','Palavras de relação: preposições e conjunções.'),
('CFO|LÍNGUA INGLESA|15.0','CFO','LÍNGUA INGLESA','15.0','Derivação de palavras (prefixação e sufixação). Semântica: sinonímia e antonímia.'),
('CFO|MATEMÁTICA|1.0','CFO','MATEMÁTICA','1.0','Conjuntos numéricos: Naturais, Inteiros, Racionais, Reais e Complexos.'),
('CFO|MATEMÁTICA|1.1','CFO','MATEMÁTICA','1.1','Operações, propriedades e aplicações.'),
('CFO|MATEMÁTICA|1.2','CFO','MATEMÁTICA','1.2','Sequências numéricas: progressão aritmética e geométrica.'),
('CFO|MATEMÁTICA|2.0','CFO','MATEMÁTICA','2.0','Álgebra: expressões algébricas.'),
('CFO|MATEMÁTICA|2.1','CFO','MATEMÁTICA','2.1','Polinômios: operações e propriedades.'),
('CFO|MATEMÁTICA|2.2','CFO','MATEMÁTICA','2.2','Equações polinomiais e inequações relacionadas.'),
('CFO|MATEMÁTICA|3.0','CFO','MATEMÁTICA','3.0','Funções: generalidades.'),
('CFO|MATEMÁTICA|3.1','CFO','MATEMÁTICA','3.1','Função do 1º grau, 2º grau e modular.'),
('CFO|MATEMÁTICA|3.2','CFO','MATEMÁTICA','3.2','Função exponencial e logarítmica. Gráficos e propriedades.'),
('CFO|MATEMÁTICA|4.0','CFO','MATEMÁTICA','4.0','Sistemas lineares, matrizes e determinantes.'),
('CFO|MATEMÁTICA|5.0','CFO','MATEMÁTICA','5.0','Análise combinatória: arranjos, permutações e combinações simples.'),
('CFO|MATEMÁTICA|5.1','CFO','MATEMÁTICA','5.1','Binômio de Newton.'),
('CFO|MATEMÁTICA|5.2','CFO','MATEMÁTICA','5.2','Probabilidade em espaços amostrais finitos.'),
('CFO|MATEMÁTICA|6.0','CFO','MATEMÁTICA','6.0','Geometria e medidas.'),
('CFO|MATEMÁTICA|6.1','CFO','MATEMÁTICA','6.1','Geometria plana: figuras, congruência, semelhança, perímetro e área.'),
('CFO|MATEMÁTICA|6.2','CFO','MATEMÁTICA','6.2','Geometria espacial: paralelismo, perpendicularismo, áreas e volumes dos sólidos.'),
('CFO|MATEMÁTICA|6.3','CFO','MATEMÁTICA','6.3','Geometria analítica no plano: retas, circunferência e distâncias.'),
('CFO|MATEMÁTICA|7.0','CFO','MATEMÁTICA','7.0','Trigonometria: razões, funções, fórmulas de transformação, equações e triângulos.'),
('CFO|MATEMÁTICA|8.0','CFO','MATEMÁTICA','8.0','Proporcionalidade e finanças.'),
('CFO|MATEMÁTICA|8.1','CFO','MATEMÁTICA','8.1','Grandezas proporcionais, porcentagem, acréscimos e descontos.'),
('CFO|MATEMÁTICA|8.2','CFO','MATEMÁTICA','8.2','Juros: capitalização simples e composta.'),
('CFO|MATEMÁTICA|9.0','CFO','MATEMÁTICA','9.0','Tratamento da informação: estatística descritiva, tabelas, medidas de tendência central e de dispersão, gráficos.'),
('CFO|MATEMÁTICA|10.0','CFO','MATEMÁTICA','10.0','Resolução de problemas envolvendo frações, conjuntos, porcentagens e sequências.'),
('CFO|INFORMÁTICA|1.0','CFO','INFORMÁTICA','1.0','Editores de texto, planilhas e apresentações (Word/Writer, Excel/Calc, PowerPoint/Impress).'),
('CFO|INFORMÁTICA|2.0','CFO','INFORMÁTICA','2.0','Sistemas operacionais Windows 7, Windows 10 e Linux.'),
('CFO|INFORMÁTICA|3.0','CFO','INFORMÁTICA','3.0','Organização e gerenciamento de informações, arquivos, pastas e programas.'),
('CFO|INFORMÁTICA|4.0','CFO','INFORMÁTICA','4.0','Atalhos de teclado, ícones, área de trabalho e lixeira.'),
('CFO|INFORMÁTICA|5.0','CFO','INFORMÁTICA','5.0','Conceitos básicos de Internet e intranet.'),
('CFO|INFORMÁTICA|6.0','CFO','INFORMÁTICA','6.0','Correio eletrônico.'),
('CFO|INFORMÁTICA|7.0','CFO','INFORMÁTICA','7.0','Computação em nuvem.'),
('CFO|INFORMÁTICA|8.0','CFO','INFORMÁTICA','8.0','Certificação e assinatura digital.'),
('CFO|INFORMÁTICA|9.0','CFO','INFORMÁTICA','9.0','Segurança da informação.'),
('CFO|INFORMÁTICA|10.0','CFO','INFORMÁTICA','10.0','Componentes de um computador.'),
('CFO|INFORMÁTICA|11.0','CFO','INFORMÁTICA','11.0','Dispositivos de armazenamento, processadores, memórias e periféricos.'),
('CFO|HISTÓRIA|1.0','CFO','HISTÓRIA','1.0','Antiguidade.'),
('CFO|HISTÓRIA|2.0','CFO','HISTÓRIA','2.0','Mundo Medieval.'),
('CFO|HISTÓRIA|3.0','CFO','HISTÓRIA','3.0','Mundo Moderno.'),
('CFO|HISTÓRIA|4.0','CFO','HISTÓRIA','4.0','Mundo Contemporâneo.'),
('CFO|HISTÓRIA|5.0','CFO','HISTÓRIA','5.0','Brasil Colônia.'),
('CFO|HISTÓRIA|6.0','CFO','HISTÓRIA','6.0','Brasil Império.'),
('CFO|HISTÓRIA|7.0','CFO','HISTÓRIA','7.0','Brasil República (de 1889 aos dias atuais).'),
('CFO|HISTÓRIA|8.0','CFO','HISTÓRIA','8.0','Aspectos do desenvolvimento cultural e científico do Brasil no século XX.'),
('CFO|HISTÓRIA|9.0','CFO','HISTÓRIA','9.0','A globalização e as questões ambientais.'),
('CFO|HISTÓRIA|10.0','CFO','HISTÓRIA','10.0','História da Bahia.'),
('CFO|HISTÓRIA|10.1','CFO','HISTÓRIA','10.1','Independência da Bahia.'),
('CFO|HISTÓRIA|10.2','CFO','HISTÓRIA','10.2','Revolta de Canudos.'),
('CFO|HISTÓRIA|10.3','CFO','HISTÓRIA','10.3','Revolta dos Malês.'),
('CFO|HISTÓRIA|10.4','CFO','HISTÓRIA','10.4','Conjuração Baiana.'),
('CFO|HISTÓRIA|10.5','CFO','HISTÓRIA','10.5','Sabinada.'),
('CFO|HISTÓRIA|11.0','CFO','HISTÓRIA','11.0','Atualidades.'),
('CFO|GEOGRAFIA|1.0','CFO','GEOGRAFIA','1.0','Relação sociedade-natureza: mecanismos da natureza.'),
('CFO|GEOGRAFIA|1.1','CFO','GEOGRAFIA','1.1','Recursos naturais e sobrevivência humana.'),
('CFO|GEOGRAFIA|1.2','CFO','GEOGRAFIA','1.2','Desigualdades na distribuição e apropriação dos recursos naturais no mundo.'),
('CFO|GEOGRAFIA|1.3','CFO','GEOGRAFIA','1.3','Uso dos recursos naturais e preservação do meio ambiente.'),
('CFO|GEOGRAFIA|2.0','CFO','GEOGRAFIA','2.0','Estruturação econômica, social e política do espaço mundial.'),
('CFO|GEOGRAFIA|2.1','CFO','GEOGRAFIA','2.1','Capitalismo, industrialização e transnacionalização do capital.'),
('CFO|GEOGRAFIA|2.2','CFO','GEOGRAFIA','2.2','Economias industriais e não industriais: articulação e desigualdades.'),
('CFO|GEOGRAFIA|2.3','CFO','GEOGRAFIA','2.3','Transformações na relação cidade-campo.'),
('CFO|GEOGRAFIA|2.4','CFO','GEOGRAFIA','2.4','Industrialização e desenvolvimento tecnológico: dominação e subordinação político-econômica.'),
('CFO|GEOGRAFIA|2.5','CFO','GEOGRAFIA','2.5','Papel do Estado e das organizações político-econômicas na produção do espaço.'),
('CFO|GEOGRAFIA|2.6','CFO','GEOGRAFIA','2.6','Mobilidade espacial e crescimento demográfico: fundamentos econômicos, sociais e políticos.'),
('CFO|GEOGRAFIA|2.7','CFO','GEOGRAFIA','2.7','Divisão Internacional e Territorial do Trabalho.'),
('CFO|GEOGRAFIA|2.8','CFO','GEOGRAFIA','2.8','Fim da Guerra Fria, desagregação da URSS e Nova Ordem Econômica Mundial.'),
('CFO|GEOGRAFIA|3.0','CFO','GEOGRAFIA','3.0','Processo de ocupação e produção do espaço brasileiro.'),
('CFO|GEOGRAFIA|3.1','CFO','GEOGRAFIA','3.1','Formação territorial do Brasil e sua relação com a natureza.'),
('CFO|GEOGRAFIA|3.2','CFO','GEOGRAFIA','3.2','Industrialização brasileira e internacionalização do capital.'),
('CFO|GEOGRAFIA|3.3','CFO','GEOGRAFIA','3.3','Urbanização, metropolização e qualidade de vida.'),
('CFO|GEOGRAFIA|3.4','CFO','GEOGRAFIA','3.4','Estrutura e produção agrária e impactos ambientais.'),
('CFO|GEOGRAFIA|3.5','CFO','GEOGRAFIA','3.5','População: crescimento, estrutura, migrações, condições de vida e de trabalho.'),
('CFO|GEOGRAFIA|3.6','CFO','GEOGRAFIA','3.6','Papel do Estado e políticas territoriais.'),
('CFO|GEOGRAFIA|3.7','CFO','GEOGRAFIA','3.7','Regionalização do Brasil: desenvolvimento desigual e combinado.'),
('CFO|DIREITO CONSTITUCIONAL|1.0','CFO','DIREITO CONSTITUCIONAL','1.0','Constituição da República Federativa do Brasil.'),
('CFO|DIREITO CONSTITUCIONAL|1.1','CFO','DIREITO CONSTITUCIONAL','1.1','Dos princípios fundamentais.'),
('CFO|DIREITO CONSTITUCIONAL|1.2','CFO','DIREITO CONSTITUCIONAL','1.2','Dos direitos e garantias fundamentais.'),
('CFO|DIREITO CONSTITUCIONAL|1.2.1','CFO','DIREITO CONSTITUCIONAL','1.2.1','Direitos e deveres individuais e coletivos.'),
('CFO|DIREITO CONSTITUCIONAL|1.2.2','CFO','DIREITO CONSTITUCIONAL','1.2.2','Da nacionalidade.'),
('CFO|DIREITO CONSTITUCIONAL|1.2.3','CFO','DIREITO CONSTITUCIONAL','1.2.3','Dos direitos políticos.'),
('CFO|DIREITO CONSTITUCIONAL|1.3','CFO','DIREITO CONSTITUCIONAL','1.3','Da organização do Estado.'),
('CFO|DIREITO CONSTITUCIONAL|1.3.1','CFO','DIREITO CONSTITUCIONAL','1.3.1','Da Administração Pública.'),
('CFO|DIREITO CONSTITUCIONAL|1.3.2','CFO','DIREITO CONSTITUCIONAL','1.3.2','Dos militares dos Estados, do Distrito Federal e dos Territórios.'),
('CFO|DIREITO CONSTITUCIONAL|1.4','CFO','DIREITO CONSTITUCIONAL','1.4','Da Defesa do Estado e das Instituições Democráticas.'),
('CFO|DIREITO CONSTITUCIONAL|1.4.1','CFO','DIREITO CONSTITUCIONAL','1.4.1','Das Forças Armadas.'),
('CFO|DIREITO CONSTITUCIONAL|1.4.2','CFO','DIREITO CONSTITUCIONAL','1.4.2','Da segurança pública.'),
('CFO|DIREITO CONSTITUCIONAL|2.0','CFO','DIREITO CONSTITUCIONAL','2.0','Constituição do Estado da Bahia.'),
('CFO|DIREITO CONSTITUCIONAL|2.1','CFO','DIREITO CONSTITUCIONAL','2.1','Dos servidores públicos militares.'),
('CFO|DIREITO CONSTITUCIONAL|2.2','CFO','DIREITO CONSTITUCIONAL','2.2','Do Poder Executivo: disposições gerais e atribuições do Governador do Estado.'),
('CFO|DIREITO CONSTITUCIONAL|2.3','CFO','DIREITO CONSTITUCIONAL','2.3','Da Justiça Militar.'),
('CFO|DIREITO CONSTITUCIONAL|2.4','CFO','DIREITO CONSTITUCIONAL','2.4','Da Segurança Pública.'),
('CFO|DIREITO CONSTITUCIONAL|2.5','CFO','DIREITO CONSTITUCIONAL','2.5','Da Família.'),
('CFO|DIREITO CONSTITUCIONAL|2.6','CFO','DIREITO CONSTITUCIONAL','2.6','Dos Direitos Específicos da Mulher.'),
('CFO|DIREITO CONSTITUCIONAL|2.7','CFO','DIREITO CONSTITUCIONAL','2.7','Da Criança e do Adolescente.'),
('CFO|DIREITO CONSTITUCIONAL|2.8','CFO','DIREITO CONSTITUCIONAL','2.8','Do Idoso.'),
('CFO|DIREITO CONSTITUCIONAL|2.9','CFO','DIREITO CONSTITUCIONAL','2.9','Do Deficiente.'),
('CFO|DIREITO CONSTITUCIONAL|2.10','CFO','DIREITO CONSTITUCIONAL','2.10','Do Negro.'),
('CFO|DIREITO CONSTITUCIONAL|2.11','CFO','DIREITO CONSTITUCIONAL','2.11','Do Índio.'),
('CFO|DIREITOS HUMANOS|1.0','CFO','DIREITOS HUMANOS','1.0','Declaração Universal dos Direitos Humanos (1948).'),
('CFO|DIREITOS HUMANOS|2.0','CFO','DIREITOS HUMANOS','2.0','Convenção Americana sobre Direitos Humanos/1969 - Pacto de São José da Costa Rica (arts. 1º ao 32).'),
('CFO|DIREITOS HUMANOS|3.0','CFO','DIREITOS HUMANOS','3.0','Convenção Internacional sobre a Eliminação de Todas as Formas de Discriminação Racial (Decreto nº 65.810/69).'),
('CFO|DIREITOS HUMANOS|4.0','CFO','DIREITOS HUMANOS','4.0','Convenção sobre Eliminação de Todas as Formas de Discriminação contra a Mulher (Decreto nº 4.377/02).'),
('CFO|DIREITOS HUMANOS|5.0','CFO','DIREITOS HUMANOS','5.0','Estatuto da Igualdade Racial e de Combate à Intolerância Religiosa (Lei Estadual nº 13.182/14).'),
('CFO|DIREITO ADMINISTRATIVO|1.0','CFO','DIREITO ADMINISTRATIVO','1.0','Princípios fundamentais da administração pública.'),
('CFO|DIREITO ADMINISTRATIVO|2.0','CFO','DIREITO ADMINISTRATIVO','2.0','Poderes administrativos.'),
('CFO|DIREITO ADMINISTRATIVO|2.1','CFO','DIREITO ADMINISTRATIVO','2.1','Poder vinculado, discricionário, hierárquico, disciplinar e regulamentar.'),
('CFO|DIREITO ADMINISTRATIVO|2.2','CFO','DIREITO ADMINISTRATIVO','2.2','Poder de polícia; uso e abuso do poder.'),
('CFO|DIREITO ADMINISTRATIVO|3.0','CFO','DIREITO ADMINISTRATIVO','3.0','Atos administrativos.'),
('CFO|DIREITO ADMINISTRATIVO|3.1','CFO','DIREITO ADMINISTRATIVO','3.1','Conceito, atributos e requisitos.'),
('CFO|DIREITO ADMINISTRATIVO|3.2','CFO','DIREITO ADMINISTRATIVO','3.2','Classificação e extinção.'),
('CFO|DIREITO ADMINISTRATIVO|4.0','CFO','DIREITO ADMINISTRATIVO','4.0','Organização administrativa.'),
('CFO|DIREITO ADMINISTRATIVO|4.1','CFO','DIREITO ADMINISTRATIVO','4.1','Órgãos públicos: conceito e classificação.'),
('CFO|DIREITO ADMINISTRATIVO|4.2','CFO','DIREITO ADMINISTRATIVO','4.2','Entidades administrativas: conceito e espécies.'),
('CFO|DIREITO ADMINISTRATIVO|5.0','CFO','DIREITO ADMINISTRATIVO','5.0','Agentes públicos: classificação.'),
('CFO|DIREITO ADMINISTRATIVO|6.0','CFO','DIREITO ADMINISTRATIVO','6.0','Regime jurídico do militar estadual.'),
('CFO|DIREITO ADMINISTRATIVO|6.1','CFO','DIREITO ADMINISTRATIVO','6.1','Estatuto dos Policiais Militares do Estado da Bahia (Lei Estadual nº 7.990/01 - arts. 1º a 92).'),
('CFO|DIREITO ADMINISTRATIVO|7.0','CFO','DIREITO ADMINISTRATIVO','7.0','Lei Geral de Proteção de Dados Pessoais - LGPD (Lei nº 13.709/2018 - arts. 1º a 32).'),
('CFO|DIREITO PENAL|1.0','CFO','DIREITO PENAL','1.0','Da aplicação da lei penal.'),
('CFO|DIREITO PENAL|1.1','CFO','DIREITO PENAL','1.1','Lei penal no tempo.'),
('CFO|DIREITO PENAL|1.2','CFO','DIREITO PENAL','1.2','Lei penal no espaço.'),
('CFO|DIREITO PENAL|2.0','CFO','DIREITO PENAL','2.0','Do crime.'),
('CFO|DIREITO PENAL|2.1','CFO','DIREITO PENAL','2.1','Elementos.'),
('CFO|DIREITO PENAL|2.2','CFO','DIREITO PENAL','2.2','Consumação e tentativa.'),
('CFO|DIREITO PENAL|2.3','CFO','DIREITO PENAL','2.3','Desistência voluntária e arrependimento eficaz.'),
('CFO|DIREITO PENAL|2.4','CFO','DIREITO PENAL','2.4','Arrependimento posterior.'),
('CFO|DIREITO PENAL|2.5','CFO','DIREITO PENAL','2.5','Crime impossível.'),
('CFO|DIREITO PENAL|2.6','CFO','DIREITO PENAL','2.6','Causas de exclusão de ilicitude e culpabilidade.'),
('CFO|DIREITO PENAL|3.0','CFO','DIREITO PENAL','3.0','Crimes contra a pessoa (homicídio, feminicídio, lesão corporal, calúnia, difamação e injúria).'),
('CFO|DIREITO PENAL|4.0','CFO','DIREITO PENAL','4.0','Crimes contra a liberdade pessoal (constrangimento ilegal, ameaça, sequestro e cárcere privado).'),
('CFO|DIREITO PENAL|5.0','CFO','DIREITO PENAL','5.0','Crimes contra o patrimônio (furto, roubo, extorsão, apropriação indébita, receptação).'),
('CFO|DIREITO PENAL|6.0','CFO','DIREITO PENAL','6.0','Crimes contra a dignidade sexual (estupro, importunação sexual, assédio sexual, estupro de vulnerável, corrupção de menores).'),
('CFO|DIREITO PENAL|7.0','CFO','DIREITO PENAL','7.0','Crimes contra a paz pública (incitação ao crime, apologia de crime ou criminoso).'),
('CFO|DIREITO PENAL|8.0','CFO','DIREITO PENAL','8.0',' Crimes contra a administração pública (peculato, concussão, corrupção passiva, prevaricação, condescendência criminosa, resistência, desobediência, desacato, corrupção ativa, contrabando).'),
('CFO|DIREITO PROCESSUAL PENAL|1.0','CFO','DIREITO PROCESSUAL PENAL','1.0','Princípios do Processo Penal.'),
('CFO|DIREITO PROCESSUAL PENAL|2.0','CFO','DIREITO PROCESSUAL PENAL','2.0','Inquérito Policial.'),
('CFO|DIREITO PROCESSUAL PENAL|3.0','CFO','DIREITO PROCESSUAL PENAL','3.0','Da prova: conceito, finalidade e obrigatoriedade; exame de corpo de delito.'),
('CFO|DIREITO PROCESSUAL PENAL|4.0','CFO','DIREITO PROCESSUAL PENAL','4.0','Da prisão (arts. 283 a 309 do CPP).'),
('CFO|DIREITO PROCESSUAL PENAL|5.0','CFO','DIREITO PROCESSUAL PENAL','5.0','Lei das Contravenções Penais (Decreto-Lei nº 3.688/41).'),
('CFO|DIREITO PROCESSUAL PENAL|5.1','CFO','DIREITO PROCESSUAL PENAL','5.1','Contravenções penais quanto a preconceito de raça, cor, sexo ou estado civil (Lei nº 7.437/85).'),
('CFO|DIREITO PROCESSUAL PENAL|6.0','CFO','DIREITO PROCESSUAL PENAL','6.0','Lei nº 13.869/19 (sanções civis e administrativas; crimes e penas de abuso de autoridade).'),
('CFO|DIREITO PROCESSUAL PENAL|7.0','CFO','DIREITO PROCESSUAL PENAL','7.0','Estatuto da Criança e do Adolescente (Lei nº 8.069/90 - arts. 1º a 6º; 15 a 18-B; 98 a 130; 225 a 258).'),
('CFO|DIREITO PROCESSUAL PENAL|8.0','CFO','DIREITO PROCESSUAL PENAL','8.0','Lei que define os crimes resultantes de preconceito de raça ou de cor (Lei nº 7.716/89).'),
('CFO|DIREITO PROCESSUAL PENAL|9.0','CFO','DIREITO PROCESSUAL PENAL','9.0','Estatuto da Pessoa com Deficiência (Lei nº 13.146/15 - arts. 1º a 13; 88 a 91).'),
('CFO|DIREITO PROCESSUAL PENAL|10.0','CFO','DIREITO PROCESSUAL PENAL','10.0','Crimes de Tortura (Lei nº 9.455/97).'),
('CFO|DIREITO PROCESSUAL PENAL|11.0','CFO','DIREITO PROCESSUAL PENAL','11.0','Estatuto do Idoso (Lei nº 10.741/03 - arts. 1º a 10).'),
('CFO|DIREITO PROCESSUAL PENAL|12.0','CFO','DIREITO PROCESSUAL PENAL','12.0','Lei Maria da Penha (Lei nº 11.340/06).'),
('CFO|DIREITO PROCESSUAL PENAL|13.0','CFO','DIREITO PROCESSUAL PENAL','13.0','Sistema nacional de políticas públicas sobre drogas (Lei nº 11.343/06 - arts. 1º a 4º, 33 a 39).'),
('CFO|DIREITO PENAL MILITAR|1.0','CFO','DIREITO PENAL MILITAR','1.0','Crimes militares em tempo de paz.'),
('CFO|DIREITO PENAL MILITAR|1.1','CFO','DIREITO PENAL MILITAR','1.1',' Crimes contra a autoridade ou disciplina militar (motim, revolta, aliciação, incitamento, violência contra superior ou militar de serviço, desrespeito a superior e a símbolo nacional ou à farda, insubordinação, resistência).'),
('CFO|DIREITO PENAL MILITAR|1.2','CFO','DIREITO PENAL MILITAR','1.2',' Crimes contra o serviço e o dever militar (insubmissão, criação ou simulação de incapacidade física, deserção - arts. 187 a 194, abandono de posto, descumprimento de missão, embriaguez em serviço, dormir em serviço).'),
('CFO|DIREITO PENAL MILITAR|1.3','CFO','DIREITO PENAL MILITAR','1.3','Crimes contra a Administração Militar (desacato e desobediência).'),
('CFO|DIREITO PROCESSUAL PENAL MILITAR|1.0','CFO','DIREITO PROCESSUAL PENAL MILITAR','1.0','Do Inquérito Policial Militar.'),
('CFO|DIREITO PROCESSUAL PENAL MILITAR|2.0','CFO','DIREITO PROCESSUAL PENAL MILITAR','2.0','Da prisão em flagrante.'),
('CFO|DIREITO PROCESSUAL PENAL MILITAR|3.0','CFO','DIREITO PROCESSUAL PENAL MILITAR','3.0','Da deserção em geral.'),
('CFO|DIREITO PROCESSUAL PENAL MILITAR|3.1','CFO','DIREITO PROCESSUAL PENAL MILITAR','3.1','Do processo de deserção do oficial.'),
('CFO|DIREITO PROCESSUAL PENAL MILITAR|3.2','CFO','DIREITO PROCESSUAL PENAL MILITAR','3.2','Do processo de deserção de praça com ou sem graduação e de praça especial.');
create function private.flash_action(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare run public.flashcard_runs;s public.method_studies;r public.method_reviews;c public.cycles;b jsonb;st jsonb;cards jsonb;d integer;choice text;correct_n integer;wrong_n integer;forgot_n integer;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 if payload->>'action'='start' then
 if payload->>'review_id' is not null then
 select * into r from public.method_reviews where id=(payload->>'review_id')::uuid and student_id=auth.uid();
 select * into s from public.method_studies where id=r.study_id;
 select * into c from public.cycles where id=s.cycle_id;
 if r.id is null or not private.review_flash_required(r) then raise exception 'Flashcards não programados para esta revisão';end if;
 else
 select * into c from public.cycles where id=(payload->>'cycle_id')::uuid and student_id=auth.uid() and status='Publicado';
 select x into b from jsonb_array_elements(c.blocks)x where x->>'id'=payload->>'block_id';
 select x into st from jsonb_array_elements(private.method_config(b->'method')->'steps')x where x->>'id'=payload->>'step_id';
 if st is null or not private.flash_required(c,b,st) then raise exception 'Flashcards disponíveis apenas para assuntos já estudados, a partir da segunda semana';end if;
 insert into public.method_studies(student_id,cycle_id,block_id,topic_key,subject,topic,studied_day,config) values(auth.uid(),c.id,b->>'id',b->>'topic_key',b->>'subject',b->>'topic',private.plan_position(c.id,auth.uid()),private.method_config(b->'method')) on conflict(cycle_id,block_id) do nothing;
 select * into s from public.method_studies where cycle_id=c.id and block_id=b->>'id';
 end if;
 d:=private.plan_position(c.id,auth.uid());
 if d<8 or (r.id is not null and r.due_day>d) or (b is not null and (b->>'date')::date-c.start_date+1>d) then raise exception 'Esta revisão ainda não está disponível';end if;
 select * into run from public.flashcard_runs where student_id=auth.uid() and ((r.id is not null and review_id=r.id) or (r.id is null and study_id=s.id and step_id=st->>'id'));
 if run.id is not null then return to_jsonb(run);end if;
 select jsonb_agg(jsonb_build_object('id',f.id,'front',f.front,'back',f.back) order by f.created_at,f.id) into cards from public.flashcards f where f.topic_key=s.topic_key and (r.id is null or r.review_key=any(f.review_keys));
 if cards is null then raise exception 'Nenhum flashcard disponível';end if;
 insert into public.flashcard_runs(student_id,cycle_id,study_id,review_id,step_id,topic_key,plan_day,cards) values(auth.uid(),c.id,s.id,r.id,case when r.id is null then st->>'id' end,s.topic_key,d,cards) returning * into run;
 perform private.touch_study_day(c.id);return to_jsonb(run);
 end if;
 select * into run from public.flashcard_runs where id=(payload->>'run_id')::uuid and student_id=auth.uid() for update;
 if run.id is null then raise exception 'Revisão não encontrada';end if;
 if payload->>'action'<>'answer' then raise exception 'Ação inválida';end if;
 choice:=payload->>'choice';
 if choice is null or choice not in ('correct','wrong','forgot') or not exists(select 1 from jsonb_array_elements(run.cards)x where x->>'id'=payload->>'card_id') then raise exception 'Resposta inválida';end if;
 if run.completed_at is not null or run.answers ? (payload->>'card_id') then return to_jsonb(run);end if;
 run.answers:=run.answers||jsonb_build_object(payload->>'card_id',choice);
 if (select count(*) from jsonb_object_keys(run.answers))=jsonb_array_length(run.cards) then
 run.completed_at:=now();select * into s from public.method_studies where id=run.study_id;
 if run.step_id is not null then update public.method_studies set flags=flags||jsonb_build_object(run.step_id,true) where id=s.id;end if;
 insert into public.progress(student_id,key,flags) values(auth.uid(),'edital|'||run.topic_key,'{"flashcards":true}') on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;

 end if;
 update public.flashcard_runs set answers=run.answers,completed_at=run.completed_at where id=run.id;
 perform private.touch_study_day(run.cycle_id);return to_jsonb(run);
end;$$;
create function public.flash_action(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.flash_action(payload);$$;

-- Only RPCs may advance plan position or mark computed block completion.
create function private.protect_plan_progress() returns trigger language plpgsql set search_path='' as $$begin
 if current_user='authenticated' and new.key not like 'edital|%' then raise exception 'Conclua as atividades pelo plano de estudos';end if;return new;
end;$$;
create trigger plan_progress_write before insert or update on public.progress for each row execute function private.protect_plan_progress();
create function private.syllabus_event() returns trigger language plpgsql security definer set search_path='' as $$
declare k text;begin
 if new.key not like 'edital|%' then return new;end if;
 for k in select jsonb_object_keys(new.flags) loop
 if new.flags->>k='true' and (tg_op='INSERT' or coalesce(old.flags->>k,'false')<>'true') then insert into public.topic_events(student_id,topic_key,kind) values(new.student_id,substr(new.key,8),k);end if;
 end loop;return new;
end;$$;
create trigger syllabus_events after insert or update on public.progress for each row execute function private.syllabus_event();
create function private.link_study_log() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.method_studies;c public.cycles;begin
 if new.origin='external' then new.cycle_id:=null;new.plan_day:=null;new.topic_key:=null;end if;
 if new.method_study_id is not null then select * into s from public.method_studies where id=new.method_study_id;new.topic_key:=s.topic_key;new.cycle_id:=s.cycle_id;end if;
 if new.topic_key is null then select t.key into new.topic_key from public.syllabus_topics t join public.profiles p on p.career=t.career where p.id=new.student_id and lower(trim(t.subject))=lower(trim(new.subject)) and lower(trim(t.title))=lower(trim(new.topic)) limit 1;end if;
 if new.cycle_id is null then select * into c from public.cycles where student_id=new.student_id and status='Publicado' and exists(select 1 from jsonb_array_elements(blocks)b where b->>'topic_key'=new.topic_key) order by created_at desc limit 1;new.cycle_id:=c.id;end if;
 if new.cycle_id is not null and new.plan_day is null then new.plan_day:=private.plan_position(new.cycle_id,new.student_id);end if;
 return new;
end;$$;
create trigger study_log_link before insert on public.study_logs for each row execute function private.link_study_log();
create function private.after_study_log() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.total>0 and new.topic_key is not null then
 insert into public.progress(student_id,key,flags) values(new.student_id,'edital|'||new.topic_key,'{"questions":true}') on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 end if;
 if new.total>new.correct and length(trim(coalesce(new.error_reason,'')))>0 and exists(select 1 from public.profiles where id=new.student_id and plan='Estratégico') then
 insert into public.errors(student_id,subject,topic,reason,source,body,explanation,log_id) values(new.student_id,new.subject,new.topic,left(new.error_reason,150),new.source,(new.total-new.correct)::text||' erros em '||new.total||' questões de '||new.topic,coalesce(new.notes,''),new.id) on conflict(log_id) do nothing;
 end if;return new;
end;$$;
create trigger study_log_sync after insert or update of error_reason on public.study_logs for each row execute function private.after_study_log();

create or replace function private.advance_method_day(cycle_uuid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles;v jsonb;d integer;last_day integer;begin
 select * into c from public.cycles where id=cycle_uuid and student_id=auth.uid() and status='Publicado' for update;
 if c.id is null or not public.is_member() then raise exception 'Ciclo não encontrado';end if;
 if exists(select 1 from public.study_sessions where student_id=auth.uid() and status='running') then raise exception 'Pause ou encerre a sessão antes de avançar';end if;
 v:=private.touch_study_day(c.id);d:=(v->>'day')::integer;
 if not (v->>'complete')::boolean then raise exception 'Conclua as etapas e revisões pendentes antes de avançar';end if;
 last_day:=greatest(c.duration_days,coalesce((select max(due_day) from public.method_reviews where cycle_id=c.id and status<>'cancelled'),0));
 if d>=last_day then return v||jsonb_build_object('finished',true,'message','Ciclo concluído. O mentor pode continuar ou renovar seu plano.');end if;
 update public.cycle_days set advanced_at=coalesce(advanced_at,now()) where cycle_id=c.id and day=d;
 insert into public.progress(student_id,key,flags) values(auth.uid(),c.id::text||'|position',jsonb_build_object('day',d+1)) on conflict(student_id,key) do update set flags=excluded.flags;
 perform private.touch_study_day(c.id);
 return jsonb_build_object('day',d+1,'message','Próximo dia liberado.');
end;$$;
alter table public.study_logs add column credited_study_id uuid references public.method_studies(id) on delete set null;
update public.study_logs l set topic_key=s.topic_key,cycle_id=s.cycle_id,plan_day=s.studied_day from public.method_studies s where l.method_study_id=s.id;
create or replace function private.validate_method(c jsonb) returns void language plpgsql set search_path='' as $$
declare r jsonb; begin
 if jsonb_typeof(c)<>'object' or (c->>'initial_questions')::integer not between 1 and 500 or (c->>'extra_questions')::integer not between 1 and 500 or (c->>'extra_after')::integer not between 1 and 365 or (c->>'reinforce_below')::integer not between 0 and 99 or (c->>'good_from')::integer not between 1 and 100 or (c->>'reinforce_below')::integer >= (c->>'good_from')::integer then raise exception 'Configuração de método inválida'; end if;
 if jsonb_typeof(c->'reviews') is distinct from 'array' or jsonb_array_length(c->'reviews')>20 or jsonb_typeof(c->'steps') is distinct from 'array' or jsonb_array_length(c->'steps') not between 1 and 12 then raise exception 'Confira as etapas e revisões do método'; end if;
 for r in select * from jsonb_array_elements(c->'reviews') loop
 if coalesce(r->>'id','')='' or coalesce((r->>'after')::integer,0) not between 1 and 365 or coalesce((r->>'questions')::integer,0) not between 1 and 500 then raise exception 'Revisão inválida'; end if;
 end loop;
 for r in select * from jsonb_array_elements(c->'steps') loop
 if coalesce(r->>'id','')='' or coalesce(r->>'title','')='' or coalesce(r->>'kind','') not in ('study','questions','flashcard','task','summary') then raise exception 'Etapa inválida'; end if;
 end loop;
 if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'steps') x) or (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'reviews') x) then raise exception 'Etapas e revisões precisam ter identificadores únicos'; end if;
end; $$;
create or replace function private.record_method_action(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles; s public.method_studies; r public.method_reviews; b jsonb; cfg jsonb; stage jsonb; rv jsonb; day integer; total_count integer; correct_count integer; minimum integer; log_key text; message text:='Etapa concluída e revisões atualizadas.'; completed boolean; has_study boolean; prior_done boolean;
begin
 if auth.uid() is null or not public.is_member() then raise exception 'Entre com um acesso liberado'; end if;
 if payload->>'action'='review' then
 select * into r from public.method_reviews where id=(payload->>'review_id')::uuid and student_id=auth.uid();
 if r.id is null then raise exception 'Revisão não encontrada';end if;
 select * into c from public.cycles where id=r.cycle_id and student_id=auth.uid() for update;
 select * into r from public.method_reviews where id=r.id;
 select * into s from public.method_studies where id=r.study_id;cfg:=s.config;minimum:=r.questions;log_key:=r.review_key;
 if r.status='completed' then return jsonb_build_object('message','Esta revisão já foi registrada.');end if;
 if r.status<>'pending' then raise exception 'Esta revisão foi cancelada';end if;
 else
 select * into c from public.cycles where id=(payload->>'cycle_id')::uuid and student_id=auth.uid() for update;
 if c.id is null or c.status<>'Publicado' then raise exception 'Ciclo não encontrado ou ainda não publicado';end if;
 select value into b from jsonb_array_elements(c.blocks) where value->>'id'=payload->>'block_id';
 if b is null then raise exception 'Assunto não encontrado';end if;
 cfg:=private.method_config(b->'method');perform private.validate_method(cfg);
 select value into stage from jsonb_array_elements(cfg->'steps') where value->>'id'=payload->>'step_id';
 if stage->>'kind'='flashcard' then raise exception 'Responda os flashcards na tela de revisão';end if;
 if stage is null then raise exception 'Etapa não encontrada';end if;
 log_key:=stage->>'id';minimum:=(cfg->>'initial_questions')::integer;
 end if;
 select greatest(1,coalesce((flags->>'day')::integer,1)) into day from public.progress where student_id=auth.uid() and key=c.id::text||'|position';day:=coalesce(day,1);
 if r.id is not null and r.due_day>day then raise exception 'A revisão ficará disponível no Dia %',r.due_day;end if;
 if r.id is null then
 if ((b->>'date')::date-coalesce(c.start_date,(select min((x->>'date')::date) from jsonb_array_elements(c.blocks) x))+1)>day then raise exception 'Esta etapa pertence a um próximo dia do ciclo';end if;
 insert into public.method_studies(student_id,cycle_id,block_id,topic_key,subject,topic,studied_day,config) values(auth.uid(),c.id,b->>'id',b->>'topic_key',b->>'subject',b->>'topic',day,cfg) on conflict(cycle_id,block_id) do nothing;
 select * into s from public.method_studies where cycle_id=c.id and block_id=b->>'id';
 if coalesce((s.flags->>log_key)::boolean,false) then return jsonb_build_object('message','Esta etapa já foi registrada.');end if;
 end if;
 if r.id is not null or stage->>'kind'='questions' then
 if coalesce((payload->>'use_existing')::boolean,false) then
 select coalesce(sum(total),0),coalesce(sum(correct),0) into total_count,correct_count from public.study_logs where student_id=auth.uid() and cycle_id=c.id and topic_key=s.topic_key and origin in ('external','platform') and (credited_study_id is null or credited_study_id=s.id);
 else total_count:=(payload->>'total')::integer;correct_count:=(payload->>'correct')::integer;end if;
 if total_count is null or correct_count is null or total_count<minimum or total_count>100000 or correct_count<0 or correct_count>total_count then raise exception 'Informe ao menos % questões e acertos entre zero e o total',minimum;end if;
 if coalesce(payload->>'understanding','') not in ('bem','revisar','dificuldade') then raise exception 'Selecione como você está no assunto';end if;
 if not coalesce((payload->>'use_existing')::boolean,false) then
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes,notes,method_study_id,method_review_id,method_step_id,understanding) values(auth.uid(),(now() at time zone 'America/Bahia')::date,s.subject,s.topic,case when r.id is null then 'Método: questões' else 'Método: revisão' end,'method',total_count,correct_count,0,left(coalesce(payload->>'notes',''),5000),s.id,r.id,case when r.id is null then log_key end,payload->>'understanding');
 else update public.study_logs set credited_study_id=s.id where student_id=auth.uid() and cycle_id=c.id and topic_key=s.topic_key and origin in ('external','platform') and credited_study_id is null;end if;
 if length(trim(coalesce(payload->>'error_reason','')))>0 then update public.study_logs set error_reason=payload->>'error_reason' where method_study_id=s.id and ((r.id is not null and method_review_id=r.id) or (r.id is null and method_step_id=log_key));end if;
 if r.id is not null then update public.method_reviews set status='completed',completed_at=now() where id=r.id;end if;
 if correct_count*100.0/total_count<(cfg->>'reinforce_below')::integer and (cfg->>'extra_enabled')::boolean then
 insert into public.method_reviews(student_id,cycle_id,study_id,review_key,after_days,due_day,questions,extra) values(auth.uid(),c.id,s.id,'extra:'||coalesce(r.id::text,log_key),(cfg->>'extra_after')::integer,day+(cfg->>'extra_after')::integer,(cfg->>'extra_questions')::integer,true) on conflict(study_id,review_key) do nothing;
 message:='Resultado salvo. Assunto em Dificuldades e revisão extra criada.';
 else message:='Resultado salvo e desempenho atualizado.';end if;
 end if;
 if r.id is null then
 s.flags:=s.flags||jsonb_build_object(log_key,true);
 has_study:=exists(select 1 from jsonb_array_elements(cfg->'steps') st where st->>'kind'='study');
 if s.studied_at is null and (stage->>'kind'='study' or not has_study) then
 s.studied_at:=now();s.studied_day:=day;
 for rv in select * from jsonb_array_elements(cfg->'reviews') loop
 insert into public.method_reviews(student_id,cycle_id,study_id,review_key,after_days,due_day,questions) values(auth.uid(),c.id,s.id,rv->>'id',(rv->>'after')::integer,day+(rv->>'after')::integer,(rv->>'questions')::integer) on conflict(study_id,review_key) do nothing;
 end loop;
 end if;
 update public.method_studies set flags=s.flags,studied_at=s.studied_at,studied_day=s.studied_day,config=cfg where id=s.id;
 completed:=not exists(select 1 from jsonb_array_elements(cfg->'steps') st where (st->>'kind'<>'flashcard' or private.flash_required(c,b,st)) and not coalesce((s.flags->>(st->>'id'))::boolean,false));
 insert into public.progress(student_id,key,flags) values(auth.uid(),c.id::text||'|'||s.block_id,jsonb_build_object('done',completed)) on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 end if;
 insert into public.progress(student_id,key,flags) values(auth.uid(),'edital|'||s.topic_key,jsonb_build_object('study',s.studied_at is not null)) on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 if r.id is not null or stage->>'kind'='questions' then update public.progress set flags=flags||jsonb_build_object(case when r.id is not null then 'review' else 'questions' end,true) where student_id=auth.uid() and key='edital|'||s.topic_key;end if;
 if stage->>'kind'='summary' then update public.progress set flags=flags||'{"summary":true}'::jsonb where student_id=auth.uid() and key='edital|'||s.topic_key;end if;
 perform private.touch_study_day(c.id);
 return jsonb_build_object('message',message);
end; $$;
create or replace function private.start_exam(eid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ex public.exams;a public.exam_attempts;snap jsonb;visible jsonb;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into ex from public.exams where id=eid;if ex.id is null then raise exception 'Simulado não encontrado';end if;
 if not public.is_admin() and ex.career is distinct from (select career from public.profiles where id=auth.uid()) then raise exception 'Simulado de outro edital ou aguardando classificação pelo mentor';end if;
 select * into a from public.exam_attempts where student_id=auth.uid() and exam_id=eid and submitted_at is null order by started_at desc limit 1;
 if a.id is null then
 select jsonb_agg(jsonb_build_object('id',q.id,'subject',q.subject,'topic',q.topic,'body',q.body,'options',q.options,'correct_index',k.correct_index,'explanation',k.explanation) order by ord) into snap from unnest(ex.question_ids) with ordinality x(id,ord) join public.questions q on q.id=x.id join private.question_keys k on k.question_id=q.id;
 if snap is null or jsonb_array_length(snap)<>cardinality(ex.question_ids) then raise exception 'Há questões indisponíveis neste simulado';end if;
 insert into public.exam_attempts(student_id,exam_id,deadline) values(auth.uid(),eid,now()+make_interval(mins=>ex.duration)) returning * into a;
 insert into private.exam_snapshots values(a.id,snap);
 else select questions into snap from private.exam_snapshots where attempt_id=a.id;end if;
 select jsonb_agg((item-'correct_index'-'explanation')||jsonb_build_object('body',coalesce(item->>'body',q.body),'options',coalesce(item->'options',q.options)) order by n) into visible from jsonb_array_elements(snap) with ordinality x(item,n) left join public.questions q on q.id=(item->>'id')::uuid;
 return jsonb_build_object('id',a.id,'deadline',a.deadline,'questions',visible,'answers',a.saved_answers);
end;$$;
create or replace function private.get_exam_print(eid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ex public.exams;qs jsonb;aid uuid;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 select * into ex from public.exams where id=eid;if ex.id is null then raise exception 'Simulado não encontrado';end if;
 if not public.is_admin() and ex.career is distinct from (select career from public.profiles where id=auth.uid()) then raise exception 'Simulado de outro edital ou aguardando classificação pelo mentor';end if;
 if public.is_admin() then
 select jsonb_agg(to_jsonb(q)||jsonb_build_object('correct_index',k.correct_index,'explanation',k.explanation) order by n) into qs from unnest(ex.question_ids) with ordinality x(id,n) join public.questions q on q.id=x.id join private.question_keys k on k.question_id=q.id;
 else
 select id into aid from public.exam_attempts where exam_id=eid and student_id=auth.uid() and submitted_at is not null order by submitted_at desc limit 1;
 if aid is null then raise exception 'Finalize o simulado para liberar a impressão com gabarito comentado';end if;
 select jsonb_agg(item||jsonb_build_object('body',coalesce(item->>'body',q.body),'options',coalesce(item->'options',q.options)) order by n) into qs from private.exam_snapshots s cross join lateral jsonb_array_elements(s.questions) with ordinality x(item,n) left join public.questions q on q.id=(item->>'id')::uuid where s.attempt_id=aid;
 end if;
 if qs is null then raise exception 'Simulado sem questões disponíveis';end if;
 return jsonb_build_object('exam',to_jsonb(ex),'questions',qs);
end;$$;
revoke all on function private.plan_position(uuid,uuid) from public,anon,authenticated;
revoke all on function private.topic_studied(uuid,text) from public,anon,authenticated;
revoke all on function private.can_read_cards(text) from public,anon,authenticated;
grant execute on function private.can_read_cards(text) to authenticated;
revoke all on function private.flash_required(public.cycles,jsonb,jsonb) from public,anon,authenticated;
revoke all on function private.review_flash_required(public.method_reviews) from public,anon,authenticated;
revoke all on function private.day_summary(uuid) from public,anon,authenticated;
revoke all on function private.touch_study_day(uuid) from public,anon,authenticated;
grant execute on function private.touch_study_day(uuid) to authenticated;
revoke all on function public.get_study_day(uuid) from public,anon,authenticated;
grant execute on function public.get_study_day(uuid) to authenticated;
revoke all on function private.study_timer(jsonb) from public,anon,authenticated;
grant execute on function private.study_timer(jsonb) to authenticated;
revoke all on function public.study_timer(jsonb) from public,anon,authenticated;
grant execute on function public.study_timer(jsonb) to authenticated;
revoke all on function private.flash_action(jsonb) from public,anon,authenticated;
grant execute on function private.flash_action(jsonb) to authenticated;
revoke all on function public.flash_action(jsonb) from public,anon,authenticated;
grant execute on function public.flash_action(jsonb) to authenticated;
revoke all on function private.protect_plan_progress() from public,anon,authenticated;
revoke all on function private.syllabus_event() from public,anon,authenticated;
revoke all on function private.link_study_log() from public,anon,authenticated;
revoke all on function private.after_study_log() from public,anon,authenticated;
revoke all on function private.advance_method_day(uuid) from public,anon,authenticated;
grant execute on function private.advance_method_day(uuid) to authenticated;
revoke all on function private.validate_method(jsonb) from public,anon,authenticated;
grant execute on function private.validate_method(jsonb) to authenticated;
revoke all on function private.record_method_action(jsonb) from public,anon,authenticated;
grant execute on function private.record_method_action(jsonb) to authenticated;
revoke all on function private.start_exam(uuid) from public,anon,authenticated;
grant execute on function private.start_exam(uuid) to authenticated;
revoke all on function private.get_exam_print(uuid) from public,anon,authenticated;
grant execute on function private.get_exam_print(uuid) to authenticated;
commit;
