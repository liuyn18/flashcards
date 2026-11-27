create table if not exists public.review_logs (
 user_id uuid not null references auth.users(id) on delete cascade,
 event_id text not null,
 study_day date not null,
 attempts integer not null check (attempts > 0),
 remembered integer not null check (remembered between 0 and attempts),
 rating text not null check (rating in ('good','fuzzy','again','legacy')),
 primary key (user_id,event_id)
);
alter table public.review_logs enable row level security;
drop policy if exists "Read own reviews" on public.review_logs;
create policy "Read own reviews" on public.review_logs for select to authenticated using (auth.uid()=user_id);
drop policy if exists "Insert own reviews" on public.review_logs;
create policy "Insert own reviews" on public.review_logs for insert to authenticated with check (auth.uid()=user_id);
revoke all on public.review_logs from anon, authenticated;
grant select, insert on public.review_logs to authenticated;
create or replace function public.record_flashcard_review(p_card uuid,p_event text,p_day date,p_rating text)
returns void language plpgsql security invoker set search_path = '' as $$
declare old_level integer; new_level integer; delay interval; inserted integer;
begin
 if auth.uid() is null or p_rating not in ('good','fuzzy','again') or p_rating is null then raise exception 'Invalid review'; end if;
 select coalesce(level,0) into old_level from public.flashcards where id=p_card and user_id=auth.uid() for update;
 if not found then raise exception 'Card not found'; end if;
 insert into public.review_logs(user_id,event_id,study_day,attempts,remembered,rating)
 values(auth.uid(),p_event,p_day,1,case when p_rating='good' then 1 else 0 end,p_rating)
 on conflict do nothing;
 get diagnostics inserted = row_count;
 if inserted=0 then return; end if;
 new_level:=case when p_rating='good' then least(old_level+1,6) when p_rating='fuzzy' then greatest(old_level-1,0) else 0 end;
 delay:=case when p_rating='good' then make_interval(days => (array[0,1,2,4,7,15,30])[new_level+1]) when p_rating='fuzzy' then interval '1 hour' else interval '10 minutes' end;
 update public.flashcards set level=new_level,review_count=coalesce(review_count,0)+1,next_review=now()+delay,updated_at=now() where id=p_card and user_id=auth.uid();
end; $$;
revoke all on function public.record_flashcard_review(uuid,text,date,text) from public, anon;
grant execute on function public.record_flashcard_review(uuid,text,date,text) to authenticated;
