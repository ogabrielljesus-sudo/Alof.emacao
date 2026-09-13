begin;
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
 if length(trim(coalesce(payload->>'error_reason','')))>0 then update public.study_logs set error_reason=payload->>'error_reason' where (method_study_id=s.id and ((r.id is not null and method_review_id=r.id) or (r.id is null and method_step_id=log_key))) or (coalesce((payload->>'use_existing')::boolean,false) and credited_study_id=s.id);end if;
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
commit;
