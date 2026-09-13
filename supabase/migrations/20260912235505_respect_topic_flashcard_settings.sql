begin;
create or replace function private.review_flash_required(r public.method_reviews) returns boolean language sql stable security definer set search_path='' as $$
 select r.status<>'cancelled' and r.due_day>=8 and exists(select 1 from public.profiles p where p.id=r.student_id and (p.plan='Estratégico' or p.role='admin')) and exists(select 1 from public.method_studies s join public.flashcards f on f.topic_key=s.topic_key where s.id=r.study_id and s.studied_at is not null and (s.config->>'flashcard'='true' or exists(select 1 from jsonb_array_elements(s.config->'steps')st where st->>'kind'='flashcard')) and r.review_key=any(f.review_keys));
$$;

commit;
