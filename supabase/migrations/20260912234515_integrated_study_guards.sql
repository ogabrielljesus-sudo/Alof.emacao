begin;
drop policy log_insert on public.study_logs;
create policy log_insert on public.study_logs for insert to authenticated with check(origin='external' and session_id is null and credited_study_id is null and method_study_id is null and method_review_id is null and method_step_id is null and date<=(now() at time zone 'America/Bahia')::date and (public.is_admin() or (public.is_member() and student_id=auth.uid())));
create or replace function private.topic_studied(uid uuid,tkey text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.progress where student_id=uid and key='edital|'||tkey and flags->>'study'='true') or exists(select 1 from public.method_studies where student_id=uid and topic_key=tkey and studied_at is not null) or exists(select 1 from public.cycles c cross join lateral jsonb_array_elements(c.blocks)b where c.student_id=uid and c.status='Publicado' and b->>'topic_key'=tkey and b->'method'->>'studied_before'='true');
$$;
create or replace function private.flash_action(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if run.step_id is not null then
 update public.method_studies set flags=flags||jsonb_build_object(run.step_id,true) where id=s.id returning * into s;
 select * into c from public.cycles where id=s.cycle_id;select x into b from jsonb_array_elements(c.blocks)x where x->>'id'=s.block_id;
 insert into public.progress(student_id,key,flags) values(auth.uid(),c.id::text||'|'||s.block_id,jsonb_build_object('done',not exists(select 1 from jsonb_array_elements(s.config->'steps')x where (x->>'kind'<>'flashcard' or private.flash_required(c,b,x)) and not coalesce((s.flags->>(x->>'id'))::boolean,false)))) on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;
 end if;
 insert into public.progress(student_id,key,flags) values(auth.uid(),'edital|'||run.topic_key,'{"flashcards":true}') on conflict(student_id,key) do update set flags=progress.flags||excluded.flags;

 end if;
 update public.flashcard_runs set answers=run.answers,completed_at=run.completed_at where id=run.id;
 perform private.touch_study_day(run.cycle_id);return to_jsonb(run);
end;$$;
create or replace function private.sync_method_cycle() returns trigger language plpgsql security definer set search_path='' as $$
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
 completed:=not exists(select 1 from jsonb_array_elements(cfg->'steps') st where (st->>'kind'<>'flashcard' or private.flash_required(new,b,st)) and not coalesce((s.flags->>(st->>'id'))::boolean,false));
 update public.progress set flags=flags||jsonb_build_object('done',completed) where student_id=s.student_id and key=s.cycle_id::text||'|'||s.block_id;
 end loop;return new;
end;$$;
commit;
