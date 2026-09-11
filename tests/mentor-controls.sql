begin;
select set_config('test.premium',gen_random_uuid()::text,true),set_config('test.basic',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 (current_setting('test.premium')::uuid,'qa-'||current_setting('test.premium')||'@example.invalid','{"name":"Teste"}'),
 (current_setting('test.basic')::uuid,'qa-'||current_setting('test.basic')||'@example.invalid','{"name":"Teste"}');
update public.profiles set active=true,plan='Estratégico' where id=current_setting('test.premium')::uuid;
update public.profiles set active=true where id=current_setting('test.basic')::uuid;
select set_config('request.jwt.claim.sub','f71d7532-6add-44fd-b20c-94ebeb39aaae',true);
set local role authenticated;
select set_config('test.question',public.save_question('{"subject":"Teste","topic":"Teste","body":"Enunciado temporário","difficulty":"Média","options":["A","B"],"correct_index":0,"explanation":"Gabarito comentado"}'::jsonb)::text,true);
with ex as (insert into public.exams(title,duration,question_ids) values('Simulado temporário',10,array[current_setting('test.question')::uuid]) returning id) select set_config('test.exam',id::text,true) from ex;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.basic'),true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.questions where id=current_setting('test.question')::uuid) then raise exception 'Básico acessou banco'; end if;
 begin insert into public.question_comments(question_id,student_id,body) values(current_setting('test.question')::uuid,auth.uid(),'Não permitido');raise exception 'Comentário indevido';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.premium'),true);
set local role authenticated;
select set_config('test.attempt',public.start_exam(current_setting('test.exam')::uuid)->>'id',true);
do $$ declare result jsonb;begin
 result:=public.submit_exam(current_setting('test.attempt')::uuid,jsonb_build_object(current_setting('test.question'),0));
 if (result->>'score')::integer<>1 or result->'details'->0->>'explanation'<>'Gabarito comentado' then raise exception 'Correção incorreta';end if;
 insert into public.question_comments(question_id,student_id,body) values(current_setting('test.question')::uuid,auth.uid(),'Comentário temporário');
 insert into public.study_logs(student_id,date,subject,topic,source,total,correct,notes) values(auth.uid(),current_date,'Teste','Teste','Externo',5,4,'Observação temporária');
 delete from public.exams where id=current_setting('test.exam')::uuid;
 if not exists(select 1 from public.exams where id=current_setting('test.exam')::uuid) then raise exception 'Aluno excluiu simulado';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','f71d7532-6add-44fd-b20c-94ebeb39aaae',true);
set local role authenticated;
delete from public.question_comments where question_id=current_setting('test.question')::uuid;
delete from public.exams where id=current_setting('test.exam')::uuid;
do $$ begin if exists(select 1 from public.exam_attempts where id=current_setting('test.attempt')::uuid) then raise exception 'Resultado não excluído';end if;end $$;
reset role;
delete from auth.users where id=current_setting('test.premium')::uuid;
do $$ begin if exists(select 1 from public.study_logs where student_id=current_setting('test.premium')::uuid) then raise exception 'Registros órfãos após exclusão';end if;end $$;
select 'Permissões, simulado, gabarito, comentários, observações e exclusões verificados' as result;
rollback;
