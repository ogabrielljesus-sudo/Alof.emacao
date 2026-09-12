begin;
alter table public.cycles add column duration_days integer not null default 30 check(duration_days between 1 and 365);
create table public.method_templates(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 1 and 150),career text not null default 'Qualquer' check(career in ('Qualquer','CFO','Soldado')),config jsonb not null,plan jsonb not null default '{"days":30,"hours":3,"count":2,"subjects":[]}',created_at timestamptz not null default now());
create table public.method_studies(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,cycle_id uuid not null references public.cycles(id) on delete cascade,block_id text not null,topic_key text not null,subject text not null,topic text not null,studied_day integer not null,studied_at timestamptz,flags jsonb not null default '{}',config jsonb not null,unique(cycle_id,block_id));
create table public.method_reviews(id uuid primary key default gen_random_uuid(),student_id uuid not null references public.profiles(id) on delete cascade,cycle_id uuid not null references public.cycles(id) on delete cascade,study_id uuid not null references public.method_studies(id) on delete cascade,review_key text not null,after_days integer not null check(after_days between 1 and 365),due_day integer not null check(due_day between 1 and 2000),questions integer not null check(questions between 1 and 500),extra boolean not null default false,status text not null default 'pending' check(status in ('pending','completed','cancelled')),manual boolean not null default false,completed_at timestamptz,unique(study_id,review_key));
create index method_studies_student_idx on public.method_studies(student_id);
create index method_reviews_student_day_idx on public.method_reviews(student_id,cycle_id,due_day);
create index method_reviews_cycle_idx on public.method_reviews(cycle_id);
alter table public.study_logs add column method_study_id uuid references public.method_studies(id) on delete set null,add column method_review_id uuid references public.method_reviews(id) on delete set null,add column method_step_id text,add column understanding text check(understanding in ('bem','revisar','dificuldade'));
create unique index method_step_log_unique on public.study_logs(method_study_id,method_step_id) where method_review_id is null and method_study_id is not null;
create unique index method_review_log_unique on public.study_logs(method_review_id) where method_review_id is not null;
alter table public.study_logs drop constraint study_logs_origin_check;
alter table public.study_logs add constraint study_logs_origin_check check(origin in ('external','platform','exam','method'));
alter table public.method_templates enable row level security;
alter table public.method_studies enable row level security;
alter table public.method_reviews enable row level security;
revoke all on public.method_templates,public.method_studies,public.method_reviews from public,anon,authenticated;
grant select,insert,update,delete on public.method_templates to authenticated;
grant select on public.method_studies,public.method_reviews to authenticated;
create policy templates_admin on public.method_templates for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create policy method_studies_read on public.method_studies for select to authenticated using((select public.is_admin()) or ((select public.is_member()) and student_id=(select auth.uid())));
create policy method_reviews_read on public.method_reviews for select to authenticated using((select public.is_admin()) or ((select public.is_member()) and student_id=(select auth.uid())));

create function private.method_config(value jsonb) returns jsonb language sql immutable set search_path='' as $$
 select '{"initial_questions":10,"reviews":[{"id":"r1","after":1,"questions":5},{"id":"r2","after":3,"questions":5},{"id":"r3","after":7,"questions":7},{"id":"r4","after":14,"questions":10}],"reinforce_below":60,"good_from":80,"extra_enabled":true,"extra_after":3,"extra_questions":5,"priority":"Alta","studied_before":false,"flashcard":false,"resource_id":"","video_id":"","notes":"","steps":[{"id":"study","kind":"study","title":"Estudar teoria"},{"id":"questions","kind":"questions","title":"Resolver questões"}]}'::jsonb || coalesce(value,'{}'::jsonb);
$$;
create function private.validate_method(c jsonb) returns void language plpgsql set search_path='' as $$
declare r jsonb; begin
 if jsonb_typeof(c)<>'object' or (c->>'initial_questions')::integer not between 1 and 500 or (c->>'extra_questions')::integer not between 1 and 500 or (c->>'extra_after')::integer not between 1 and 365 or (c->>'reinforce_below')::integer not between 0 and 99 or (c->>'good_from')::integer not between 1 and 100 or (c->>'reinforce_below')::integer >= (c->>'good_from')::integer then raise exception 'Configuração de método inválida'; end if;
 if jsonb_typeof(c->'reviews') is distinct from 'array' or jsonb_array_length(c->'reviews')>20 or jsonb_typeof(c->'steps') is distinct from 'array' or jsonb_array_length(c->'steps') not between 1 and 12 then raise exception 'Confira as etapas e revisões do método'; end if;
 for r in select * from jsonb_array_elements(c->'reviews') loop
 if coalesce(r->>'id','')='' or coalesce((r->>'after')::integer,0) not between 1 and 365 or coalesce((r->>'questions')::integer,0) not between 1 and 500 then raise exception 'Revisão inválida'; end if;
 end loop;
 for r in select * from jsonb_array_elements(c->'steps') loop
 if coalesce(r->>'id','')='' or coalesce(r->>'title','')='' or coalesce(r->>'kind','') not in ('study','questions','flashcard','task') then raise exception 'Etapa inválida'; end if;
 end loop;
 if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'steps') x) or (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'reviews') x) then raise exception 'Etapas e revisões precisam ter identificadores únicos'; end if;
end; $$;
create function private.validate_method_rows() returns trigger language plpgsql set search_path='' as $$
declare b jsonb; c jsonb; normalized jsonb:='[]'; begin
 if tg_table_name='method_templates' then new.config:=private.method_config(new.config);perform private.validate_method(new.config);return new;end if;
 for b in select * from jsonb_array_elements(new.blocks) loop
 if tg_op='UPDATE' and exists(select 1 from public.method_studies ms where ms.cycle_id=new.id and ms.block_id=b->>'id' and ms.topic_key is distinct from b->>'topic_key') then b:=b||jsonb_build_object('id',gen_random_uuid()::text);end if;
 c:=private.method_config(b->'method');perform private.validate_method(c);normalized:=normalized||jsonb_build_array(b||jsonb_build_object('method',c));
 end loop;
 new.blocks:=normalized;return new;
end; $$;
create trigger cycles_method_validation before insert or update of blocks on public.cycles for each row execute function private.validate_method_rows();
create trigger templates_method_validation before insert or update on public.method_templates for each row execute function private.validate_method_rows();

-- Only authenticated owners of the cycle can complete stages; a cycle lock makes retries idempotent.
create function private.record_method_action(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 total_count:=(payload->>'total')::integer;correct_count:=(payload->>'correct')::integer;
 if total_count is null or correct_count is null or total_count<minimum or total_count>100000 or correct_count<0 or correct_count>total_count then raise exception 'Informe ao menos % questões e acertos entre zero e o total',minimum;end if;
 if coalesce(payload->>'understanding','') not in ('bem','revisar','dificuldade') then raise exception 'Selecione como você está no assunto';end if;
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes,notes,method_study_id,method_review_id,method_step_id,understanding) values(auth.uid(),(now() at time zone 'America/Bahia')::date,s.subject,s.topic,case when r.id is null then 'Método: questões' else 'Método: revisão' end,'method',total_count,correct_count,0,left(coalesce(payload->>'notes',''),5000),s.id,r.id,case when r.id is null then log_key end,payload->>'understanding');
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
 completed:=not exists(select 1 from jsonb_array_elements(cfg->'steps') st where not coalesce((s.flags->>(st->>'id'))::boolean,false));
 insert into public.progress(student_id,key,flags) values(auth.uid(),c.id::text||'|'||s.block_id,jsonb_build_object('done',completed)) on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 end if;
 insert into public.progress(student_id,key,flags) values(auth.uid(),'edital|'||s.topic_key,jsonb_build_object('study',s.studied_at is not null)) on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 if r.id is not null or stage->>'kind'='questions' then update public.progress set flags=flags||jsonb_build_object(case when r.id is not null then 'review' else 'questions' end,true) where student_id=auth.uid() and key='edital|'||s.topic_key;end if;
 return jsonb_build_object('message',message);
end; $$;
create function public.record_method_action(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.record_method_action(payload);$$;

create function private.advance_method_day(cycle_uuid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles; day integer; b jsonb; begin
 if auth.uid() is null or not public.is_member() then raise exception 'Acesso não liberado';end if;
 select * into c from public.cycles where id=cycle_uuid and student_id=auth.uid() and status='Publicado' for update;
 if c.id is null then raise exception 'Ciclo não encontrado';end if;
 select coalesce((flags->>'day')::integer,1) into day from public.progress where student_id=auth.uid() and key=c.id::text||'|position';day:=coalesce(day,1);
 if day>=2000 then raise exception 'O ciclo chegou ao limite de dias. Peça uma continuação ao mentor.';end if;
 for b in select * from jsonb_array_elements(c.blocks) loop
 if ((b->>'date')::date-coalesce(c.start_date,(select min((x->>'date')::date) from jsonb_array_elements(c.blocks) x))+1)<=day and not exists(select 1 from public.progress where student_id=auth.uid() and key=c.id::text||'|'||(b->>'id') and coalesce((flags->>'done')::boolean,false)) then raise exception 'Conclua as etapas pendentes deste dia antes de avançar';end if;
 end loop;
 if exists(select 1 from public.method_reviews where cycle_id=c.id and student_id=auth.uid() and due_day<=day and status='pending') then raise exception 'Conclua as revisões pendentes antes de avançar';end if;
 insert into public.progress(student_id,key,flags) values(auth.uid(),c.id::text||'|position',jsonb_build_object('day',day+1)) on conflict(student_id,key) do update set flags=excluded.flags;
 return jsonb_build_object('day',day+1);
end; $$;
create function public.advance_method_day(cycle_uuid uuid) returns jsonb language sql security invoker set search_path='' as $$select private.advance_method_day(cycle_uuid);$$;

create function private.manage_method_review(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Acesso restrito ao mentor';end if;
 if payload->>'action'='cancel' then update public.method_reviews set status='cancelled',manual=true where id=(payload->>'review_id')::uuid and status='pending';
 elsif payload->>'action'='edit' then update public.method_reviews set due_day=(payload->>'due_day')::integer,questions=(payload->>'questions')::integer,manual=true where id=(payload->>'review_id')::uuid and status='pending';
 else raise exception 'Ação inválida';end if;
 get diagnostics n=row_count;if n<>1 then raise exception 'A revisão já foi concluída, cancelada ou não existe';end if;return jsonb_build_object('updated',true);
end;$$;
create function public.manage_method_review(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.manage_method_review(payload);$$;

create function private.sync_method_cycle() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.method_studies;b jsonb;cfg jsonb;rv jsonb;completed boolean;begin
 if auth.uid() is null or not public.is_admin() then return new;end if;
 for s in select * from public.method_studies where cycle_id=new.id loop
 select value into b from jsonb_array_elements(new.blocks) where value->>'id'=s.block_id;
 if b is null or b->>'topic_key'<>s.topic_key then update public.method_reviews set status='cancelled' where study_id=s.id and status='pending';continue;end if;
 cfg:=private.method_config(b->'method');update public.method_studies set config=cfg where id=s.id;
 update public.method_reviews set status='cancelled' where study_id=s.id and not extra and status='pending' and not exists(select 1 from jsonb_array_elements(cfg->'reviews') x where x->>'id'=review_key);
 if s.studied_at is not null then for rv in select * from jsonb_array_elements(cfg->'reviews') loop
 insert into public.method_reviews(student_id,cycle_id,study_id,review_key,after_days,due_day,questions) values(s.student_id,s.cycle_id,s.id,rv->>'id',(rv->>'after')::integer,s.studied_day+(rv->>'after')::integer,(rv->>'questions')::integer)
 on conflict(study_id,review_key) do update set after_days=excluded.after_days,due_day=excluded.due_day,questions=excluded.questions where method_reviews.status='pending' and not method_reviews.manual;
 end loop;end if;
 completed:=not exists(select 1 from jsonb_array_elements(cfg->'steps') st where not coalesce((s.flags->>(st->>'id'))::boolean,false));
 update public.progress set flags=flags||jsonb_build_object('done',completed) where student_id=s.student_id and key=s.cycle_id::text||'|'||s.block_id;
 end loop;return new;
end;$$;
create trigger cycle_sync_method after update of blocks on public.cycles for each row execute function private.sync_method_cycle();


-- A simulado answer cannot be obtained from the question bank, comments, or print API before submission.
create function private.can_review_question(qid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.is_premium() and (public.is_admin() or not exists(select 1 from public.exams e where qid=any(e.question_ids)) or exists(select 1 from public.exam_attempts a join public.exams e on e.id=a.exam_id where a.student_id=auth.uid() and a.submitted_at is not null and qid=any(e.question_ids)));
$$;
create function public.can_review_question(qid uuid) returns boolean language sql stable security invoker set search_path='' as $$select private.can_review_question(qid);$$;
drop policy comments_read on public.question_comments;
create policy comments_read on public.question_comments for select to authenticated using(public.can_review_question(question_id));
drop policy comments_insert on public.question_comments;
create policy comments_insert on public.question_comments for insert to authenticated with check(student_id=(select auth.uid()) and public.can_review_question(question_id));

create function private.answer_question(qid uuid,selected integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.questions;k private.question_keys;ok boolean;begin
 if auth.uid() is null or not private.can_review_question(qid) then raise exception 'Finalize o simulado para liberar o gabarito desta questão';end if;
 select * into q from public.questions where id=qid;select * into k from private.question_keys where question_id=qid;
 if q.id is null or k.question_id is null or selected is null or selected<0 or selected>=jsonb_array_length(q.options) then raise exception 'Questão ou alternativa inválida';end if;
 ok:=selected=k.correct_index;
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes) values(auth.uid(),(now() at time zone 'America/Bahia')::date,q.subject,q.topic,'Plataforma','platform',1,case when ok then 1 else 0 end,0);
 return jsonb_build_object('correct',ok,'correct_index',k.correct_index,'explanation',k.explanation);
end;$$;
create or replace function public.answer_question(qid uuid,selected integer) returns jsonb language sql security invoker set search_path='' as $$select private.answer_question(qid,selected);$$;

alter table public.exam_attempts add column saved_answers jsonb not null default '{}';
create function private.start_exam(eid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ex public.exams;a public.exam_attempts;snap jsonb;visible jsonb;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into ex from public.exams where id=eid;if ex.id is null then raise exception 'Simulado não encontrado';end if;
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
create or replace function public.start_exam(eid uuid) returns jsonb language sql security invoker set search_path='' as $$select private.start_exam(eid);$$;

create function private.save_exam_answer(attempt_uuid uuid,qid uuid,selected integer) returns void language plpgsql security definer set search_path='' as $$
declare a public.exam_attempts;q jsonb;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Acesso não liberado';end if;
 select * into a from public.exam_attempts where id=attempt_uuid and student_id=auth.uid() for update;
 if a.id is null or a.submitted_at is not null or now()>a.deadline then raise exception 'O prazo desta tentativa foi encerrado';end if;
 select x into q from private.exam_snapshots s cross join lateral jsonb_array_elements(s.questions) x where s.attempt_id=a.id and x->>'id'=qid::text;
 if q is null or selected is null or selected<0 or selected>=jsonb_array_length(coalesce(q->'options',(select options from public.questions where id=qid))) then raise exception 'Alternativa inválida';end if;
 update public.exam_attempts set saved_answers=saved_answers||jsonb_build_object(qid::text,selected) where id=a.id;
end;$$;
create function public.save_exam_answer(attempt_uuid uuid,qid uuid,selected integer) returns void language sql security invoker set search_path='' as $$select private.save_exam_answer(attempt_uuid,qid,selected);$$;

create function private.submit_exam(attempt_id uuid,responses jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.exam_attempts;snap jsonb;q jsonb;ok boolean;scored integer:=0;results jsonb:='[]';chosen jsonb;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 if jsonb_typeof(responses) is distinct from 'object' then raise exception 'Respostas inválidas';end if;
 select * into a from public.exam_attempts where id=attempt_id and student_id=auth.uid() for update;
 if a.id is null then raise exception 'Tentativa não encontrada';end if;
 if a.submitted_at is not null then return jsonb_build_object('score',a.score,'total',a.total,'details',a.details);end if;
 chosen:=case when now()<=a.deadline then a.saved_answers||responses else a.saved_answers end;
 select questions into snap from private.exam_snapshots s where s.attempt_id=a.id;
 for q in select * from jsonb_array_elements(snap) loop
 ok:=coalesce(chosen->>(q->>'id'),'')=q->>'correct_index';if ok then scored:=scored+1;end if;
 results:=results||jsonb_build_array(jsonb_build_object('question_id',q->>'id','correct',ok,'correct_index',(q->>'correct_index')::integer,'explanation',q->>'explanation'));
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes) values(auth.uid(),(now() at time zone 'America/Bahia')::date,q->>'subject',q->>'topic','Simulado','exam',1,case when ok then 1 else 0 end,0);
 end loop;
 update public.exam_attempts set submitted_at=now(),score=scored,total=jsonb_array_length(snap),details=results,saved_answers=chosen where id=a.id;
 return jsonb_build_object('score',scored,'total',jsonb_array_length(snap),'details',results);
end;$$;
create or replace function public.submit_exam(attempt_id uuid,responses jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.submit_exam(attempt_id,responses);$$;

create function private.get_exam_print(eid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare ex public.exams;qs jsonb;aid uuid;begin
 if auth.uid() is null or not public.is_premium() then raise exception 'Recurso exclusivo do Estratégico';end if;
 select * into ex from public.exams where id=eid;if ex.id is null then raise exception 'Simulado não encontrado';end if;
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
create function public.get_exam_print(eid uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_exam_print(eid);$$;

drop policy log_insert on public.study_logs;
create policy log_insert on public.study_logs for insert to authenticated with check(origin='external' and method_study_id is null and method_review_id is null and method_step_id is null and date<=(now() at time zone 'America/Bahia')::date and (public.is_admin() or (public.is_member() and student_id=auth.uid())));

-- Invoker wrappers expose only checked operations. Private tables remain inaccessible.
grant usage on schema private to authenticated;
revoke all on function private.method_config(jsonb),private.validate_method(jsonb),private.validate_method_rows(),private.sync_method_cycle(),private.record_method_action(jsonb),private.advance_method_day(uuid),private.manage_method_review(jsonb),private.can_review_question(uuid),private.answer_question(uuid,integer),private.start_exam(uuid),private.save_exam_answer(uuid,uuid,integer),private.submit_exam(uuid,jsonb),private.get_exam_print(uuid) from public,anon,authenticated;
grant execute on function private.method_config(jsonb),private.validate_method(jsonb),private.record_method_action(jsonb),private.advance_method_day(uuid),private.manage_method_review(jsonb),private.can_review_question(uuid),private.answer_question(uuid,integer),private.start_exam(uuid),private.save_exam_answer(uuid,uuid,integer),private.submit_exam(uuid,jsonb),private.get_exam_print(uuid) to authenticated;
revoke all on function public.record_method_action(jsonb),public.advance_method_day(uuid),public.manage_method_review(jsonb),public.can_review_question(uuid),public.answer_question(uuid,integer),public.start_exam(uuid),public.save_exam_answer(uuid,uuid,integer),public.submit_exam(uuid,jsonb),public.get_exam_print(uuid) from public,anon;
grant execute on function public.record_method_action(jsonb),public.advance_method_day(uuid),public.manage_method_review(jsonb),public.can_review_question(uuid),public.answer_question(uuid,integer),public.start_exam(uuid),public.save_exam_answer(uuid,uuid,integer),public.submit_exam(uuid,jsonb),public.get_exam_print(uuid) to authenticated;

insert into public.method_templates(name,career,config,plan) values
 ('Método CFO PMBA','CFO',private.method_config('{}'),'{"days":30,"hours":3,"count":2,"subjects":[]}'),
 ('Método Soldado PMBA','Soldado',private.method_config('{}'),'{"days":30,"hours":3,"count":2,"subjects":[]}'),
 ('Método Iniciante','Qualquer',private.method_config('{"initial_questions":10}'),'{"days":30,"hours":2,"count":2,"subjects":[]}'),
 ('Método Intensivo','Qualquer',private.method_config('{"initial_questions":20}'),'{"days":30,"hours":4,"count":3,"subjects":[]}'),
 ('Método Aluno com dificuldade em Matemática','Qualquer',private.method_config('{"priority":"Muito alta","flashcard":false,"notes":"Retome a explicação dos erros antes de avançar para o próximo assunto."}'),'{"days":30,"hours":2,"count":2,"subjects":[]}');
commit;
