-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – Erweiterung: Witz des Tages, Profile, Autoren-Rangliste,
-- Duell, Reaktionen, Wochen-Challenge, Hinweise, Statistik und Witz-Vorrat.
--
-- Für eine SCHON eingerichtete Datenbank: einmal komplett im Supabase SQL Editor
-- ausführen (Run). Mehrfach ausführen ist unschädlich.
-- Bei einer Neueinrichtung nicht nötig: supabase.sql enthält diesen Teil bereits.
-- ═══════════════════════════════════════════════════════════════════

-- ───────────────────────── Neue Tabellen und Spalten ─────────────────────────

-- Witz des Tages: jeden Abend um 20 Uhr (deutsche Zeit) wird der beste Witz der letzten 24 Stunden gekrönt
create table if not exists public.daily_winners (
  day         date primary key,
  joke_id     bigint not null references public.jokes on delete cascade,
  crowned_at  timestamptz not null default now()
);
create index if not exists daily_winners_joke on public.daily_winners (joke_id);

-- Reaktionen: 😂 (lol), 🙄 (sigh), 💀 (dead) – eine pro Gerät und Witz
create table if not exists public.reactions (
  joke_id     bigint not null references public.jokes on delete cascade,
  device_id   uuid   not null,
  ip_hash     text,
  kind        text   not null check (kind in ('lol', 'sigh', 'dead')),
  created_at  timestamptz not null default now(),
  primary key (joke_id, device_id)
);
create index if not exists reactions_recent on public.reactions (created_at);
create index if not exists reactions_ip     on public.reactions (ip_hash, created_at);

-- Duell: zwei Witze nebeneinander, Elo-Wertung
alter table public.jokes add column if not exists elo        double precision not null default 1000;
alter table public.jokes add column if not exists duel_count int not null default 0;
create table if not exists public.duel_votes (
  id          bigint generated always as identity primary key,
  winner      bigint not null references public.jokes on delete cascade,
  loser       bigint not null references public.jokes on delete cascade,
  device_id   uuid   not null,
  ip_hash     text,
  created_at  timestamptz not null default now()
);
create unique index if not exists duel_votes_pair on public.duel_votes (device_id, least(winner, loser), greatest(winner, loser));
create index if not exists duel_votes_ip on public.duel_votes (ip_hash, created_at);
create index if not exists duel_votes_recent on public.duel_votes (created_at);

-- Wochen-Challenge: ein Thema mit eigener Rangliste
create table if not exists public.challenges (
  id           serial primary key,
  title        text not null check (char_length(title) between 3 and 80),
  description  text not null default '' check (char_length(description) <= 300),
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  created_at   timestamptz not null default now(),
  check (ends_at > starts_at)
);
alter table public.jokes add column if not exists challenge_id int references public.challenges on delete set null;
create index if not exists jokes_challenge on public.jokes (challenge_id) where challenge_id is not null;

-- Für die Statistik
create index if not exists votes_recent on public.votes (created_at);
create index if not exists jokes_recent on public.jokes (created_at);

-- ───────────────────────── Witz des Tages ─────────────────────────

-- Krönt alle abgeschlossenen Tage (max. 7 zurück), die noch keinen Sieger haben.
-- Wird bei jedem Aufruf der Highlights mit erledigt, ein Zeitplan ist nicht nötig.
create or replace function public.crown_pending() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_local timestamp := now() at time zone 'Europe/Berlin';
  v_last  date := case when v_local::time >= time '20:00' then v_local::date else v_local::date - 1 end;
  v_day   date;
  v_end   timestamptz;
  v_joke  bigint;
begin
  select coalesce(max(w.day) + 1, v_last - 6) into v_day from public.daily_winners w;
  if v_day < v_last - 6 then v_day := v_last - 6; end if;
  while v_day <= v_last loop
    v_end := (v_day + time '20:00') at time zone 'Europe/Berlin';
    v_joke := null;
    -- 1. Wahl: bester Witz der 24 Stunden bis 20 Uhr
    select j.id into v_joke from public.jokes j
    where j.status = 'visible' and j.created_at > v_end - interval '24 hours' and j.created_at <= v_end
      and j.up_count >= 1
      and not exists (select 1 from public.daily_winners w where w.joke_id = j.id)
    order by public.wilson_lower(j.up_count, j.down_count) desc, j.up_count desc, j.created_at
    limit 1;
    -- Ruhiger Tag: bester noch nicht gekrönter Witz der letzten 7 Tage
    if v_joke is null then
      select j.id into v_joke from public.jokes j
      where j.status = 'visible' and j.created_at > v_end - interval '7 days' and j.created_at <= v_end
        and j.up_count >= 1
        and not exists (select 1 from public.daily_winners w where w.joke_id = j.id)
      order by public.wilson_lower(j.up_count, j.down_count) desc, j.up_count desc, j.created_at
      limit 1;
    end if;
    if v_joke is not null then
      insert into public.daily_winners (day, joke_id) values (v_day, v_joke) on conflict do nothing;
    end if;
    v_day := v_day + 1;
  end loop;
end $$;

-- Die letzten gekrönten Witze, neuester zuerst
create or replace function public.get_daily(p_device uuid, p_limit int default 7)
returns table (day date, id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language plpgsql volatile security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.crown_pending();
  return query
    select w.day, f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
           (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value
    from public.daily_winners w
    join public.joke_feed f on f.id = w.joke_id and f.status = 'visible'
    left join public.votes v on v.joke_id = f.id and v.device_id = p_device
    order by w.day desc
    limit least(greatest(p_limit, 1), 60);
end $$;

-- ───────────────────────── Reaktionen ─────────────────────────

create or replace function public.set_reaction(p_device uuid, p_joke bigint, p_kind text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  h        text := public.client_ip_hash();
  v_author uuid;
  v_user   uuid;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  select j.author_device, j.author_user into v_author, v_user from public.jokes j
  where j.id = p_joke and j.status = 'visible' and j.created_at <= now();
  if not found then raise exception 'joke_not_found'; end if;
  if v_author = p_device or (v_user is not null and v_user = auth.uid()) then raise exception 'own_joke'; end if;

  if p_kind is null or p_kind = '' then
    delete from public.reactions r where r.joke_id = p_joke and r.device_id = p_device;
    return;
  end if;
  if p_kind not in ('lol', 'sigh', 'dead') then raise exception 'invalid_value'; end if;
  if not exists (select 1 from public.reactions r where r.joke_id = p_joke and r.device_id = p_device)
     and (select count(*) from public.reactions r where r.ip_hash = h and r.created_at > now() - interval '1 hour') >= 300 then
    raise exception 'rate_limited';
  end if;
  insert into public.reactions (joke_id, device_id, ip_hash, kind) values (p_joke, p_device, h, p_kind)
  on conflict (joke_id, device_id) do update set kind = excluded.kind;
end $$;

-- Zähler für eine Liste von Witzen (und die eigene Reaktion)
create or replace function public.get_reactions(p_device uuid, p_ids bigint[])
returns table (joke_id bigint, lol int, sigh int, dead int, mine text)
language sql stable security definer set search_path = public as $$
  select r.joke_id,
         count(*) filter (where r.kind = 'lol')::int,
         count(*) filter (where r.kind = 'sigh')::int,
         count(*) filter (where r.kind = 'dead')::int,
         max(r.kind) filter (where r.device_id = p_device)
  from public.reactions r
  where r.joke_id = any(coalesce(p_ids[1:200], '{}'))
  group by r.joke_id
$$;

-- Meiste Reaktionen einer Art in den letzten 7 Tagen (z. B. „Größter Seufzer der Woche“)
create or replace function public.get_reaction_top(p_device uuid, p_kind text, p_limit int default 3)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint, n int)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value, t.n
  from (select r.joke_id, count(*)::int as n from public.reactions r
        where r.kind = p_kind and r.created_at > now() - interval '7 days'
        group by r.joke_id) t
  join public.joke_feed f on f.id = t.joke_id and f.status = 'visible'
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  order by t.n desc, f.score desc
  limit least(greatest(p_limit, 1), 20)
$$;

-- ───────────────────────── Duell ─────────────────────────

-- Zwei Witze mit ähnlicher Duell-Wertung, die dieses Gerät noch nicht gegeneinander hatte
create or replace function public.get_duel(p_device uuid)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language plpgsql volatile security definer set search_path = public as $$
#variable_conflict use_column
declare
  a bigint; a_elo double precision; b bigint;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  for i in 1..5 loop
    select j.id, j.elo into a, a_elo from public.jokes j
    where j.status = 'visible' and j.created_at <= now() and j.author_device <> p_device
      and (auth.uid() is null or j.author_user is null or j.author_user <> auth.uid())
    order by (j.duel_count < 10) desc, random()
    limit 1;
    if a is null then return; end if;
    select j.id into b from public.jokes j
    where j.status = 'visible' and j.created_at <= now() and j.id <> a and j.author_device <> p_device
      and (auth.uid() is null or j.author_user is null or j.author_user <> auth.uid())
      and not exists (select 1 from public.duel_votes d where d.device_id = p_device
                        and least(d.winner, d.loser) = least(a, j.id) and greatest(d.winner, d.loser) = greatest(a, j.id))
    order by abs(j.elo - a_elo) + random() * 150
    limit 1;
    exit when b is not null;
  end loop;
  if b is null then return; end if;
  return query
    select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score, false, v.value
    from public.joke_feed f
    left join public.votes v on v.joke_id = f.id and v.device_id = p_device
    where f.id in (a, b)
    order by random();
end $$;

create or replace function public.cast_duel(p_device uuid, p_winner bigint, p_loser bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare
  h   text := public.client_ip_hash();
  ew  double precision; el double precision; exp_w double precision;
  k   constant double precision := 24;
  n   int;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  if p_winner is null or p_loser is null or p_winner = p_loser then raise exception 'invalid_value'; end if;
  if (select count(*) from public.duel_votes d where d.ip_hash = h and d.created_at > now() - interval '1 hour') >= 300 then
    raise exception 'rate_limited';
  end if;
  -- Zeilen sperren, damit gleichzeitige Duelle sich nicht überschreiben (feste Reihenfolge gegen Deadlocks)
  perform 1 from public.jokes j where j.id in (p_winner, p_loser) and j.status = 'visible' order by j.id for update;
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'joke_not_found'; end if;
  if exists (select 1 from public.jokes j where j.id in (p_winner, p_loser)
             and (j.author_device = p_device or (j.author_user is not null and j.author_user = auth.uid()))) then
    raise exception 'own_joke';
  end if;
  insert into public.duel_votes (winner, loser, device_id, ip_hash) values (p_winner, p_loser, p_device, h)
  on conflict do nothing;
  if not found then return; end if;   -- dieses Paar hat das Gerät schon entschieden
  select j.elo into ew from public.jokes j where j.id = p_winner;
  select j.elo into el from public.jokes j where j.id = p_loser;
  exp_w := 1 / (1 + power(10, (el - ew) / 400));
  update public.jokes j set elo = j.elo + k * (1 - exp_w), duel_count = j.duel_count + 1 where j.id = p_winner;
  update public.jokes j set elo = j.elo - k * (1 - exp_w), duel_count = j.duel_count + 1 where j.id = p_loser;
end $$;

-- Duell-Champions: beste Elo-Wertung ab 5 Duellen
create or replace function public.get_duel_ranking(p_device uuid, p_limit int default 10)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint,
               elo int, duels int)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value,
         round(j.elo)::int, j.duel_count
  from public.jokes j
  join public.joke_feed f on f.id = j.id and f.status = 'visible'
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  where j.duel_count >= 5
  order by j.elo desc
  limit least(greatest(p_limit, 1), 50)
$$;

-- ───────────────────────── Autoren und Profile ─────────────────────────

-- Witzbold-Rangliste: Wilson-Score über alle Stimmen eines Autors.
-- Mindestens 5 Stimmen (Woche) bzw. 20 (Alltime), damit Masse allein nicht gewinnt.
create or replace function public.get_author_ranking(p_range text, p_limit int default 30)
returns table (username text, jokes int, up_count int, down_count int, score double precision)
language sql stable security definer set search_path = public as $$
  select p.username, count(*)::int, sum(f.up_count)::int, sum(f.down_count)::int,
         public.wilson_lower(sum(f.up_count)::double precision, sum(f.down_count)::double precision)
  from public.joke_feed f
  join public.profiles p on p.id = f.author_user
  where f.status = 'visible'
    and (p_range = 'all' or f.created_at > now() - interval '7 days')
  group by p.id, p.username
  having sum(f.up_count + f.down_count) >= case when p_range = 'all' then 20 else 5 end
  order by 5 desc, 3 desc
  limit least(greatest(p_limit, 1), 100)
$$;

-- Sieger beendeter Challenges (bester Beitrag mit mindestens einem Like)
create or replace view public.challenge_winners as
  select c.id as challenge_id, w.id as joke_id, w.author_user
  from public.challenges c
  cross join lateral (
    select j.id, j.author_user from public.jokes j
    where j.challenge_id = c.id and j.status = 'visible' and j.up_count >= 1
    order by public.wilson_lower(j.up_count, j.down_count) desc, j.up_count desc, j.created_at
    limit 1) w
  where c.ends_at <= now();

create or replace function public.get_profile(p_name text)
returns table (username text, member_since timestamptz, jokes int, up_count int, down_count int,
               top_up int, crowns int, challenge_wins int, best_rank int)
language sql stable security definer set search_path = public as $$
  select p.username, p.created_at,
         count(j.id)::int, coalesce(sum(j.up_count), 0)::int, coalesce(sum(j.down_count), 0)::int,
         coalesce(max(j.up_count), 0)::int,
         (select count(*) from public.daily_winners w join public.jokes x on x.id = w.joke_id where x.author_user = p.id)::int,
         (select count(*) from public.challenge_winners cw where cw.author_user = p.id)::int,
         (select min(r.rk) from (
            select f.author_user, row_number() over (order by f.score desc, f.up_count + f.down_count desc, f.created_at desc) as rk
            from public.joke_feed f where f.status = 'visible' and f.created_at > now() - interval '24 hours') r
          where r.author_user = p.id)::int
  from public.profiles p
  left join public.jokes j on j.author_user = p.id and j.status = 'visible' and j.created_at <= now()
  where lower(p.username) = lower(trim(p_name))
  group by p.id, p.username, p.created_at
$$;

create or replace function public.get_profile_jokes(p_device uuid, p_name text, p_limit int default 30, p_offset int default 0)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value
  from public.joke_feed f
  join public.profiles p on p.id = f.author_user and lower(p.username) = lower(trim(p_name))
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  where f.status = 'visible'
  order by f.score desc, f.up_count desc, f.created_at desc
  limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0)
$$;

-- Hinweise für angemeldete Autoren: Platz 1–3 heute, Witz des Tages, Like-Meilensteine
create or replace function public.my_highlights()
returns table (kind text, joke_id bigint, value int, body text)
language plpgsql volatile security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;
  perform public.crown_pending();
  return query
    select 'rank'::text, r.id, r.rk::int, r.body from (
      select f.id, f.body, f.author_user,
             row_number() over (order by f.score desc, f.up_count + f.down_count desc, f.created_at desc) as rk
      from public.joke_feed f where f.status = 'visible' and f.created_at > now() - interval '24 hours') r
    where r.author_user = v_user and r.rk <= 3
    union all
    select 'crown', j.id, to_char(w.day, 'YYYYMMDD')::int, j.body
    from public.daily_winners w join public.jokes j on j.id = w.joke_id
    where j.author_user = v_user and w.day > current_date - 7
    union all
    select 'likes', j.id,
           (select max(m) from unnest(array[10, 25, 50, 100, 250, 500, 1000]) m where m <= j.up_count), j.body
    from public.jokes j
    where j.author_user = v_user and j.status = 'visible' and j.up_count >= 10;
end $$;

-- ───────────────────────── Challenge ─────────────────────────

-- Witz posten und (falls aktiv) bei der Challenge einreichen
create or replace function public.post_joke(p_device uuid, p_category text, p_body text, p_challenge int)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
begin
  v_id := public.post_joke(p_device, p_category, p_body);
  if p_challenge is not null and exists (
       select 1 from public.challenges c where c.id = p_challenge and now() >= c.starts_at and now() < c.ends_at) then
    update public.jokes j set challenge_id = p_challenge where j.id = v_id;
  end if;
  return v_id;
end $$;

-- Laufende und die letzten beendeten Challenges
create or replace function public.get_challenges()
returns table (id int, title text, description text, starts_at timestamptz, ends_at timestamptz,
               active boolean, entries int, winner_name text, winner_joke bigint)
language sql stable security definer set search_path = public as $$
  select c.id, c.title, c.description, c.starts_at, c.ends_at,
         now() >= c.starts_at and now() < c.ends_at,
         (select count(*) from public.jokes j where j.challenge_id = c.id and j.status = 'visible')::int,
         (select x.author_name from public.jokes x where x.id = cw.joke_id), cw.joke_id
  from public.challenges c
  left join public.challenge_winners cw on cw.challenge_id = c.id
  where c.starts_at <= now()
  order by (now() < c.ends_at) desc, c.ends_at desc
  limit 6
$$;

create or replace function public.get_challenge_ranking(p_device uuid, p_challenge int, p_limit int default 30)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value
  from public.joke_feed f
  join public.jokes j on j.id = f.id and j.challenge_id = p_challenge
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  where f.status = 'visible'
  order by f.score desc, f.up_count + f.down_count desc, f.created_at desc
  limit least(greatest(p_limit, 1), 100)
$$;

-- Challenge anlegen (p_id null) oder ändern
create or replace function public.admin_save_challenge(p_key text, p_id int, p_title text, p_description text,
                                                       p_starts timestamptz, p_ends timestamptz)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_id int;
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then raise exception 'invalid_value'; end if;
  if p_id is null then
    insert into public.challenges (title, description, starts_at, ends_at)
    values (trim(p_title), trim(coalesce(p_description, '')), p_starts, p_ends) returning challenges.id into v_id;
  else
    update public.challenges c set title = trim(p_title), description = trim(coalesce(p_description, '')),
           starts_at = p_starts, ends_at = p_ends where c.id = p_id returning c.id into v_id;
  end if;
  return v_id;
end $$;

-- ───────────────────────── Statistik und Vorrat (Admin) ─────────────────────────

create or replace function public.admin_stats(p_key text, p_days int default 14)
returns table (day date, votes int, voters int, reactions int, duels int, new_jokes int, signups int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  return query
    with d as (
      select g::date as day,
             (g::date::timestamp at time zone 'Europe/Berlin') as t0,
             ((g::date + 1)::timestamp at time zone 'Europe/Berlin') as t1
      from generate_series((now() at time zone 'Europe/Berlin')::date - (least(greatest(p_days, 1), 90) - 1),
                           (now() at time zone 'Europe/Berlin')::date, interval '1 day') g)
    select d.day,
      (select count(*) from public.votes v where v.created_at >= d.t0 and v.created_at < d.t1)::int,
      (select count(distinct x.dev) from (
         select v.device_id as dev from public.votes v where v.created_at >= d.t0 and v.created_at < d.t1
         union all select r.device_id from public.reactions r where r.created_at >= d.t0 and r.created_at < d.t1
         union all select q.device_id from public.duel_votes q where q.created_at >= d.t0 and q.created_at < d.t1) x)::int,
      (select count(*) from public.reactions r where r.created_at >= d.t0 and r.created_at < d.t1)::int,
      (select count(*) from public.duel_votes q where q.created_at >= d.t0 and q.created_at < d.t1)::int,
      (select count(*) from public.jokes j where j.author_user is not null and j.created_at >= d.t0 and j.created_at < d.t1)::int,
      (select count(*) from public.profiles p where p.created_at >= d.t0 and p.created_at < d.t1)::int
    from d order by d.day;
end $$;

create or replace function public.admin_totals(p_key text)
returns table (jokes int, user_jokes int, users int, votes int, devices int, queued int, queue_until timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  return query select
    (select count(*) from public.jokes j where j.status = 'visible' and j.created_at <= now())::int,
    (select count(*) from public.jokes j where j.status = 'visible' and j.author_user is not null)::int,
    (select count(*) from public.profiles)::int,
    (select count(*) from public.votes)::int,
    (select count(distinct v.device_id) from public.votes v)::int,
    (select count(*) from public.jokes j where j.status = 'visible' and j.created_at > now())::int,
    (select max(j.created_at) from public.jokes j where j.status = 'visible' and j.created_at > now());
end $$;

create or replace function public.admin_category_stats(p_key text)
returns table (slug text, name text, jokes int, queued int, votes_week int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  return query
    select c.slug, c.name,
      (select count(*) from public.jokes j where j.category_id = c.id and j.status = 'visible' and j.created_at <= now())::int,
      (select count(*) from public.jokes j where j.category_id = c.id and j.status = 'visible' and j.created_at > now())::int,
      (select count(*) from public.votes v join public.jokes j on j.id = v.joke_id
        where j.category_id = c.id and v.created_at > now() - interval '7 days')::int
    from public.categories c order by c.position;
end $$;

-- Witz-Vorrat: mehrere Witze auf einmal einplanen. Sie erscheinen nacheinander
-- (p_per_day pro Tag) im Anschluss an die schon geplanten Witze. Duplikate werden übersprungen.
create or replace function public.admin_bulk_add(p_key text, p_category text, p_bodies text[], p_per_day int)
returns table (inserted int, skipped int)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_cat   int;
  v_start timestamptz;
  v_step  interval := interval '24 hours' / least(greatest(coalesce(p_per_day, 3), 1), 48);
  v_body  text;
  v_norm  text;
  v_ins   int := 0;
  v_skip  int := 0;
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  select c.id into v_cat from public.categories c where c.slug = p_category;
  if v_cat is null then raise exception 'invalid_category'; end if;
  select greatest(now(), coalesce(max(j.created_at), now())) into v_start
  from public.jokes j where j.status = 'visible' and j.author_user is null and j.created_at > now();
  foreach v_body in array coalesce(p_bodies[1:500], '{}') loop
    v_body := trim(v_body);
    if char_length(v_body) not between 10 and 500 then v_skip := v_skip + 1; continue; end if;
    v_norm := public.normalize_joke(v_body);
    if exists (select 1 from public.jokes j where j.status <> 'removed' and j.body_norm % v_norm
               and similarity(j.body_norm, v_norm) >= 0.6) then
      v_skip := v_skip + 1; continue;
    end if;
    v_ins := v_ins + 1;
    insert into public.jokes (category_id, body, author_name, author_device, created_at)
    values (v_cat, v_body, 'Lachwerk', '00000000-0000-0000-0000-000000000000', v_start + v_step * v_ins);
  end loop;
  return query select v_ins, v_skip;
end $$;

-- ───────────────────────── Rechte ─────────────────────────

alter table public.daily_winners enable row level security;
alter table public.reactions     enable row level security;
alter table public.duel_votes    enable row level security;
alter table public.challenges    enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant select on public.categories to anon, authenticated;

grant execute on function
  public.get_ranking(uuid, text, text, int, int),
  public.get_joke(uuid, bigint),
  public.get_unrated(uuid, bigint[], int),
  public.find_similar(text),
  public.cast_vote(uuid, bigint, int),
  public.post_joke(uuid, text, text),
  public.post_joke(uuid, text, text, int),
  public.username_available(text),
  public.my_profile(),
  public.report_joke(uuid, bigint),
  public.admin_check(text),
  public.admin_list(text, text),
  public.admin_set_status(text, bigint, text),
  public.get_daily(uuid, int),
  public.set_reaction(uuid, bigint, text),
  public.get_reactions(uuid, bigint[]),
  public.get_reaction_top(uuid, text, int),
  public.get_duel(uuid),
  public.cast_duel(uuid, bigint, bigint),
  public.get_duel_ranking(uuid, int),
  public.get_author_ranking(text, int),
  public.get_profile(text),
  public.get_profile_jokes(uuid, text, int, int),
  public.my_highlights(),
  public.get_challenges(),
  public.get_challenge_ranking(uuid, int, int),
  public.admin_save_challenge(text, int, text, text, timestamptz, timestamptz),
  public.admin_stats(text, int),
  public.admin_totals(text),
  public.admin_category_stats(text),
  public.admin_bulk_add(text, text, text[], int)
to anon, authenticated;

-- ───────────────────────── Erste Challenge ─────────────────────────
-- Läuft bis Sonntag 20 Uhr (deutsche Zeit). Nur, wenn es noch keine Challenge gibt.
insert into public.challenges (title, description, starts_at, ends_at)
select 'Witze übers Fitnessstudio',
       'Hanteln, Laufband, Neujahrsvorsätze: Dein bester Witz rund ums Training. Der Beitrag mit dem besten Score am Sonntagabend gewinnt.',
       now(),
       case when e > now() then e else e + interval '7 days' end
from (select ((date_trunc('week', now() at time zone 'Europe/Berlin') + interval '6 days 20 hours')
              at time zone 'Europe/Berlin') as e) x
where not exists (select 1 from public.challenges);
