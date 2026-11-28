-- FSRS-4.5 default parameters; three-button mapping Again=1 Hard=2 Good=3.
alter table public.flashcards add column if not exists memory_s double precision;
alter table public.flashcards add column if not exists memory_d double precision;
alter table public.flashcards add column if not exists memory_at timestamptz;
alter table public.review_logs add column if not exists card_id uuid;
alter table public.review_logs add column if not exists reviewed_at timestamptz;
alter table public.study_tasks add column if not exists phase text not null default 'main';
create or replace function public.record_flashcard_review(p_card uuid,p_event text,p_day date,p_rating text)
returns void language plpgsql security invoker set search_path='' as $$
declare c public.flashcards%rowtype; w double precision[]:=array[0.4872,1.4003,3.7145,13.8206,5.1618,1.2298,0.8975,0.031,1.6474,0.1367,1.0461,2.1072,0.0793,0.3246,1.587,0.2272,2.8755]; g integer; s double precision; d double precision; r double precision; elapsed double precision; days integer; inserted integer; ts timestamptz:=now(); same_day boolean;
begin
 if auth.uid() is null or p_rating is null or p_rating not in ('good','fuzzy','again') then raise exception 'Invalid review'; end if;
 select * into c from public.flashcards where id=p_card and user_id=auth.uid() for update;
 if not found then raise exception 'Card not found'; end if;
 select exists(select 1 from public.review_logs where user_id=auth.uid() and card_id=p_card and study_day=p_day) into same_day;
 insert into public.review_logs(user_id,event_id,study_day,attempts,remembered,rating,card_id,reviewed_at) values(auth.uid(),p_event,p_day,1,case when p_rating='good' then 1 else 0 end,p_rating,p_card,ts) on conflict do nothing;
 get diagnostics inserted=row_count;
 if inserted=0 then return; end if;
 if same_day then
 update public.flashcards set review_count=coalesce(review_count,0)+1,updated_at=ts where id=p_card and user_id=auth.uid(); return;
 end if;
 g:=case p_rating when 'good' then 3 when 'fuzzy' then 2 else 1 end;
 if c.memory_s is null then
 if coalesce(c.review_count,0)>0 then
 s:=(array[0.4872,1,2,4,7,15,30])[greatest(0,least(6,coalesce(c.level,0)))+1]; d:=5.1618;
 else s:=w[g]; d:=greatest(1,least(10,w[5]-exp(w[6]*(g-1))+1)); end if;
 end if;
 if c.memory_s is not null or coalesce(c.review_count,0)>0 then
 s:=coalesce(c.memory_s,s); d:=coalesce(c.memory_d,d);
 elapsed:=greatest(0,extract(epoch from (ts-coalesce(c.memory_at,c.next_review-make_interval(secs=>s*86400),ts)))/86400);
 r:=power(1+19.0/81*elapsed/s,-0.5);
 if g=1 then s:=least(s,w[12]*power(d,-w[13])*(power(s+1,w[14])-1)*exp(w[15]*(1-r)));
 else s:=s*(1+exp(w[9])*(11-d)*power(s,-w[10])*(exp((1-r)*w[11])-1)*case when g=2 then w[16] else 1 end); end if;
 d:=greatest(1,least(10,w[8]*(w[5]-exp(w[6]*3)+1)+(1-w[8])*(d-w[7]*(g-3))));
 end if;
 s:=greatest(0.01,least(36500,s)); days:=greatest(1,least(36500,round(s)::integer));
 update public.flashcards set memory_s=s,memory_d=d,memory_at=ts,level=case when s>=30 then 6 when s>=7 then 4 when s>=1 then 2 else 0 end,review_count=coalesce(review_count,0)+1,next_review=ts+make_interval(days=>days),updated_at=ts where id=p_card and user_id=auth.uid();
end; $$;
-- Existing task RPC calls this replacement automatically.
