create table if not exists public.study_tasks (
 user_id uuid primary key references auth.users(id) on delete cascade,
 task_id uuid not null,
 ids uuid[] not null,
 done jsonb not null default '{}'::jsonb
);
alter table public.study_tasks enable row level security;
drop policy if exists "Own study task" on public.study_tasks;
create policy "Own study task" on public.study_tasks for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
revoke all on public.study_tasks from anon, authenticated;
grant select, insert, update on public.study_tasks to authenticated;
create or replace function public.record_task_review(p_task uuid,p_card uuid,p_event text,p_day date,p_rating text)
returns void language plpgsql security invoker set search_path='' as $$
declare t public.study_tasks%rowtype;
begin
 select * into t from public.study_tasks where user_id=auth.uid() for update;
 if not found or t.task_id<>p_task then
   -- Preserve pending reviews from a task replaced on another device.
   perform public.record_flashcard_review(p_card,p_event,p_day,p_rating);
   return;
 end if;
 if not (p_card=any(t.ids)) then raise exception 'Card not in task'; end if;
 if t.done ? p_card::text then return; end if;
 perform public.record_flashcard_review(p_card,p_event,p_day,p_rating);
 update public.study_tasks set done=done||jsonb_build_object(p_card::text,p_rating) where user_id=auth.uid();
end; $$;
revoke all on function public.record_task_review(uuid,uuid,text,date,text) from public,anon;
grant execute on function public.record_task_review(uuid,uuid,text,date,text) to authenticated;
