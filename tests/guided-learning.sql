begin;
select set_config('qa.admin',gen_random_uuid()::text,true),
       set_config('qa.student',gen_random_uuid()::text,true),
       set_config('qa.expired',gen_random_uuid()::text,true);

insert into auth.users(id,email,raw_user_meta_data)
select current_setting(k)::uuid,'qa-'||current_setting(k)||'@example.invalid','{"name":"QA guiado"}'::jsonb
from unnest(array['qa.admin','qa.student','qa.expired']) k;

update public.profiles
set active=true,
    plan='Estratégico',
    career='CFO',
    subscription_start=date '2026-09-01',
    paid_until=case when id=current_setting('qa.expired')::uuid then date '2026-09-10' else date '2026-09-30' end,
    role=case when id=current_setting('qa.admin')::uuid then 'admin' else 'student' end
where id in (current_setting('qa.admin')::uuid,current_setting('qa.student')::uuid,current_setting('qa.expired')::uuid);

select set_config('request.jwt.claim.sub',current_setting('qa.admin'),true);
set local role authenticated;
insert into public.resources(title,kind,subject,description,url,career,module_name,position,release_month)
values ('QA CFO mês 1','Material','Matemática','','https://example.com/1.pdf','CFO','Módulo 01',1,1),
       ('QA CFO mês 2','Vídeo','Matemática','','https://example.com/2','CFO','Módulo 02',1,2),
       ('QA Soldado','Material','Português','','https://example.com/3.pdf','Soldado','Módulo 01',1,1),
       ('QA Ambos','Material','Orientações','','https://example.com/4.pdf','Ambos','Comece aqui',1,1);
reset role;

select set_config('request.jwt.claim.sub',current_setting('qa.student'),true);
set local role authenticated;
do $$ begin
 if not public.is_member() then raise exception 'Aluno pago foi bloqueado'; end if;
 if (select count(*) from public.resources where title like 'QA %')<>2 then raise exception 'Liberação do primeiro mês ou do concurso incorreta'; end if;
 if exists(select 1 from public.resources where title='QA CFO mês 2') then raise exception 'Segundo mês liberado antes do pagamento'; end if;
end; $$;
reset role;

update public.profiles set paid_until=date '2026-10-31' where id=current_setting('qa.student')::uuid;
set local role authenticated;
do $$ begin
 if not exists(select 1 from public.resources where title='QA CFO mês 2') then raise exception 'Segundo mês não foi liberado após renovação'; end if;
end; $$;
reset role;

select set_config('request.jwt.claim.sub',current_setting('qa.expired'),true);
set local role authenticated;
do $$ begin
 if public.is_member() then raise exception 'Aluno vencido permaneceu ativo'; end if;
 if exists(select 1 from public.resources where title like 'QA %') then raise exception 'Conteúdo exposto para aluno vencido'; end if;
end; $$;
reset role;

select 'PASS: vencimento, renovação e módulos liberados por concurso e mês' as result;
rollback;
