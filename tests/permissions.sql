-- Run as database owner. All temporary fixtures are rolled back.
begin;
create temporary table fixture_ids(kind text,id uuid);
insert into fixture_ids values ('admin',gen_random_uuid()),('basic',gen_random_uuid()),('premium',gen_random_uuid());
insert into auth.users(id,email,raw_user_meta_data)
select id,'test-'||id||'@example.invalid','{"name":"Teste temporário"}'::jsonb from fixture_ids;
update public.profiles p set active=true,role=case when f.kind='admin' then 'admin' else 'student' end,
plan=case when f.kind='basic' then 'Básico' else 'Estratégico' end from fixture_ids f where p.id=f.id;
insert into public.cycles(student_id,title,status,blocks)
select id,'Teste de permissão','Publicado','[]'::jsonb from fixture_ids where kind in ('basic','premium');
insert into public.errors(student_id,subject,topic,reason,body)
select id,'Teste','Teste','Teste','Teste' from fixture_ids where kind='premium';
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where kind='basic'),true);
set local role authenticated;
do $$ begin
 if public.is_admin() or not public.is_member() or public.is_premium() then raise exception 'Falha no plano Básico'; end if;
 if (select count(*) from public.cycles)<>1 then raise exception 'Ciclo de outro aluno visível'; end if;
 if exists(select 1 from public.errors) then raise exception 'Básico acessou caderno de erros'; end if;
 if (select count(*) from public.profiles)<>1 then raise exception 'Perfil de outro aluno visível'; end if;
 begin
  perform public.save_question('{}'::jsonb);
  raise exception 'Aluno criou questão';
 exception when raise_exception then
  if sqlerrm<>'Acesso restrito ao administrador' then raise; end if;
 end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where kind='premium'),true);
set local role authenticated;
do $$ begin
 if not public.is_premium() or public.is_admin() then raise exception 'Falha no Estratégico'; end if;
 if (select count(*) from public.errors)<>1 then raise exception 'Caderno indisponível'; end if;
 if (select count(*) from public.cycles)<>1 then raise exception 'Ciclos sem isolamento'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where kind='admin'),true);
set local role authenticated;
do $$ begin
 if not public.is_admin() then raise exception 'Administrador indisponível'; end if;
 if (select count(*) from public.cycles)<>2 then raise exception 'Admin sem acesso aos ciclos'; end if;
end $$;
reset role;
select 'Permissões de administrador, Básico e Estratégico verificadas' as result;
rollback;
