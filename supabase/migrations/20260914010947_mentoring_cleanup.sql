begin;
create or replace function private.method_config(value jsonb) returns jsonb language sql immutable set search_path='' as $$
with cfg as(select ('{"initial_questions":10,"reviews":[{"id":"r1","after":1,"questions":5},{"id":"r2","after":3,"questions":5},{"id":"r3","after":7,"questions":7},{"id":"r4","after":14,"questions":10}],"reinforce_below":60,"good_from":80,"extra_enabled":true,"extra_after":3,"extra_questions":5,"priority":"Alta","studied_before":false,"flashcard":false,"resource_id":"","video_id":"","notes":"","steps":[{"id":"study","kind":"study","title":"Estudar teoria"},{"id":"questions","kind":"questions","title":"Resolver questões"}]}'::jsonb || coalesce(value,'{}'::jsonb))-'flashcard' as c)
select c||jsonb_build_object('reinforce_below',60,'good_from',80,'steps',coalesce((select jsonb_agg(s order by n) from jsonb_array_elements(c->'steps') with ordinality a(s,n) where s->>'kind'<>'flashcard'),'[]'::jsonb)) from cfg;
$$;
CREATE OR REPLACE FUNCTION private.validate_method(c jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r jsonb; begin
 if jsonb_typeof(c)<>'object' or (c->>'initial_questions')::integer not between 1 and 500 or (c->>'extra_questions')::integer not between 1 and 500 or (c->>'extra_after')::integer not between 1 and 365 or (c->>'reinforce_below')::integer not between 0 and 99 or (c->>'good_from')::integer not between 1 and 100 or (c->>'reinforce_below')::integer >= (c->>'good_from')::integer then raise exception 'Configuração de método inválida'; end if;
 if jsonb_typeof(c->'reviews') is distinct from 'array' or jsonb_array_length(c->'reviews')>20 or jsonb_typeof(c->'steps') is distinct from 'array' or jsonb_array_length(c->'steps') not between 0 and 12 then raise exception 'Confira as etapas e revisões do método'; end if;
 for r in select * from jsonb_array_elements(c->'reviews') loop
 if coalesce(r->>'id','')='' or coalesce((r->>'after')::integer,0) not between 1 and 365 or coalesce((r->>'questions')::integer,0) not between 1 and 500 then raise exception 'Revisão inválida'; end if;
 end loop;
 for r in select * from jsonb_array_elements(c->'steps') loop
 if coalesce(r->>'id','')='' or coalesce(r->>'title','')='' or coalesce(r->>'kind','') not in ('study','questions','task','summary') then raise exception 'Etapa inválida'; end if;
 end loop;
 if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'steps') x) or (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(c->'reviews') x) then raise exception 'Etapas e revisões precisam ter identificadores únicos'; end if;
end; $function$;

CREATE OR REPLACE FUNCTION private.after_study_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if new.total>0 and new.topic_key is not null then
 insert into public.progress(student_id,key,flags) values(new.student_id,'edital|'||new.topic_key,'{"questions":true}') on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 end if;
 return new;
end;$function$;

create or replace function private.record_method_action(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.cycles; s public.method_studies; r public.method_reviews; b jsonb; cfg jsonb; stage jsonb; rv jsonb; day integer; total_count integer; correct_count integer; minimum integer; log_key text; message text:='Etapa concluída e revisões atualizadas.'; completed boolean; has_study boolean; prior_done boolean;
begin
 if auth.uid() is null or not public.is_member() then raise exception 'Entre com um acesso liberado'; end if;
 if payload->>'action'='review' then
 select * into r from public.method_reviews where id=(payload->>'review_id')::uuid and student_id=auth.uid();
 if r.id is null then raise exception 'Revisão não encontrada';end if;
 select * into c from public.cycles where id=r.cycle_id and student_id=auth.uid() for update;
 select * into r from public.method_reviews where id=r.id;
 select * into s from public.method_studies where id=r.study_id;cfg:=private.method_config(s.config);minimum:=r.questions;log_key:=r.review_key;
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
 if coalesce((payload->>'use_existing')::boolean,false) then
 select coalesce(sum(total),0),coalesce(sum(correct),0) into total_count,correct_count from public.study_logs where student_id=auth.uid() and cycle_id=c.id and topic_key=s.topic_key and origin in ('external','platform') and (credited_study_id is null or credited_study_id=s.id);
 else total_count:=(payload->>'total')::integer;correct_count:=(payload->>'correct')::integer;end if;
 if total_count is null or correct_count is null or total_count<minimum or total_count>100000 or correct_count<0 or correct_count>total_count then raise exception 'Informe ao menos % questões e acertos entre zero e o total',minimum;end if;
 if coalesce(payload->>'understanding','') not in ('bem','revisar','dificuldade') then raise exception 'Selecione como você está no assunto';end if;
 if not coalesce((payload->>'use_existing')::boolean,false) then
 insert into public.study_logs(student_id,date,subject,topic,source,origin,total,correct,minutes,notes,method_study_id,method_review_id,method_step_id,understanding) values(auth.uid(),(now() at time zone 'America/Bahia')::date,s.subject,s.topic,case when r.id is null then 'Método: questões' else 'Método: revisão' end,'method',total_count,correct_count,0,left(coalesce(payload->>'notes',''),5000),s.id,r.id,case when r.id is null then log_key end,payload->>'understanding');
 else update public.study_logs set credited_study_id=s.id where student_id=auth.uid() and cycle_id=c.id and topic_key=s.topic_key and origin in ('external','platform') and credited_study_id is null;end if;
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
 if stage->>'kind'='summary' then update public.progress set flags=flags||'{"summary":true}'::jsonb where student_id=auth.uid() and key='edital|'||s.topic_key;end if;
 perform private.touch_study_day(c.id);
 return jsonb_build_object('message',message);
end; $$;

-- Remove disabled activities from required work without deleting historical records.
create or replace function private.flash_required(c public.cycles,b jsonb,st jsonb) returns boolean language sql stable set search_path='' as $$select false$$;
create or replace function private.review_flash_required(r public.method_reviews) returns boolean language sql stable set search_path='' as $$select false$$;
revoke all on public.flashcards,public.flashcard_runs,public.errors from anon,authenticated;
revoke all on function public.flash_action(jsonb) from public,anon,authenticated;
update public.method_studies set config=private.method_config(config);
update public.method_templates set config=private.method_config(config);
-- Existing blocks retain their identity, order and progress; only removed steps are filtered.
update public.cycles c set blocks=(select jsonb_agg(b||jsonb_build_object('method',private.method_config(b->'method')) order by n) from jsonb_array_elements(c.blocks) with ordinality a(b,n));
alter table public.exams drop constraint exams_question_ids_check;
alter table public.exams add constraint exams_question_ids_check check(cardinality(question_ids) between 1 and 80);
create function private.validate_exam_size() returns trigger language plpgsql set search_path='' as $$begin
if cardinality(new.question_ids)>80 then raise exception 'Um simulado pode ter no máximo 80 questões.';end if;return new;end;$$;
create trigger exam_size_validation before insert or update of question_ids on public.exams for each row execute function private.validate_exam_size();
revoke all on function private.validate_exam_size() from public,anon,authenticated;
commit;
