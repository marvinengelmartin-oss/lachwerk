-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – Datenbank für die Version OHNE Anmeldung
-- Einmal komplett im Supabase SQL Editor ausführen (Run).
-- Danach unten den Admin-Schlüssel setzen (letzte Zeile).
-- ═══════════════════════════════════════════════════════════════════
--
-- Prinzip: Lesen, Liken und Bewerten geht ohne Konto (zufällige Geräte-ID im Browser).
-- Zum POSTEN braucht man ein Konto (Supabase Auth, E-Mail + Passwort).
-- Besucher greifen NIE direkt auf Tabellen zu, sondern nur über die
-- Funktionen unten. Die prüfen Limits, Duplikate und eigene Witze.
-- IP-Adressen werden nur gesalzen gehasht gespeichert.

create schema if not exists extensions;
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- ───────────────────────── Tabellen ─────────────────────────

create table public.settings (
  key   text primary key,
  value text not null
);
insert into public.settings (key, value)
values ('ip_salt', encode(extensions.gen_random_bytes(16), 'hex'));

create table public.categories (
  id        serial primary key,
  slug      text unique not null,
  name      text not null,
  position  int not null default 0
);

-- Konten: Supabase Auth verwaltet E-Mail und Passwort (auth.users),
-- hier liegt nur der öffentliche Benutzername.
create table public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  username    text not null check (username ~ '^[A-Za-z0-9_.äöüÄÖÜß]{3,20}$'),
  created_at  timestamptz not null default now()
);
create unique index profiles_username_lower on public.profiles (lower(username));

-- Bei jeder Registrierung automatisch ein Profil anlegen (Name aus den Anmeldedaten)
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_name text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  i      int  := 0;
begin
  -- Ungültiger oder schon vergebener Name: Ersatzname wählen (die Registrierung darf nie scheitern)
  while v_name !~ '^[A-Za-z0-9_.äöüÄÖÜß]{3,20}$'
        or exists (select 1 from public.profiles p where lower(p.username) = lower(v_name)) loop
    i := i + 1;
    v_name := 'nutzer_' || substr(md5(new.id::text || i::text), 1, 10);
  end loop;
  insert into public.profiles (id, username) values (new.id, v_name);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Text vereinheitlichen (für den Duplikat-Check)
create function public.normalize_joke(t text) returns text
language sql immutable as $$
  select trim(regexp_replace(lower(t), '[^[:alnum:]]+', ' ', 'g'))
$$;

create table public.jokes (
  id             bigint generated always as identity primary key,
  category_id    int  not null references public.categories,
  body           text not null check (char_length(body) between 10 and 500),
  body_norm      text generated always as (public.normalize_joke(body)) stored,
  author_name    text not null check (char_length(author_name) between 2 and 24),
  author_device  uuid not null,
  author_user    uuid references auth.users on delete set null,   -- Konto des Verfassers
  ip_hash        text,
  status         text not null default 'visible' check (status in ('visible', 'hidden', 'removed')),
  up_count       int  not null default 0,
  down_count     int  not null default 0,
  report_count   int  not null default 0,
  reviewed_at    timestamptz,                 -- gesetzt, sobald die Moderation geprüft hat
  created_at     timestamptz not null default now()
);
create index jokes_visible_recent on public.jokes (created_at desc) where status = 'visible';
create index jokes_device_recent  on public.jokes (author_device, created_at desc);
create index jokes_user_recent    on public.jokes (author_user, created_at desc);
create index jokes_ip_recent      on public.jokes (ip_hash, created_at desc);
create index jokes_body_trgm      on public.jokes using gin (body_norm extensions.gin_trgm_ops);

create table public.votes (
  joke_id     bigint   not null references public.jokes on delete cascade,
  device_id   uuid     not null,
  ip_hash     text,
  value       smallint not null check (value in (-1, 1)),
  created_at  timestamptz not null default now(),
  primary key (joke_id, device_id)
);
create index votes_ip_recent  on public.votes (ip_hash, created_at);
create index votes_joke_ip    on public.votes (joke_id, ip_hash);
create index votes_device     on public.votes (device_id);

create table public.reports (
  joke_id     bigint not null references public.jokes on delete cascade,
  device_id   uuid   not null,
  ip_hash     text,
  created_at  timestamptz not null default now(),
  primary key (joke_id, device_id)
);

-- ───────────────────────── Hilfsfunktionen ─────────────────────────

-- IP des Aufrufers (von Supabase im Header übergeben), gesalzen gehasht
create function public.client_ip_hash() returns text
language sql stable security definer set search_path = public, extensions as $$
  select encode(digest(
    coalesce(trim(split_part(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1)), '')
    || (select s.value from public.settings s where s.key = 'ip_salt'),
    'sha256'), 'hex')
$$;

-- Wilson-Score (Untergrenze, 95 %): faire Sortierung auch bei wenigen Stimmen
create function public.wilson_lower(up double precision, down double precision)
returns double precision language sql immutable as $$
  select case when up + down <= 0 then 0 else
    ( up/(up+down) + 1.9208/(up+down)
      - 1.96 * sqrt( (up/(up+down)) * (1 - up/(up+down)) / (up+down) + 0.9604/((up+down)*(up+down)) ) )
    / (1 + 3.8416/(up+down))
  end
$$;

create view public.joke_feed as
  select j.id, j.body, c.slug as category_slug, j.author_name, j.author_device, j.author_user, j.created_at,
         j.up_count, j.down_count, j.report_count, j.status, j.reviewed_at,
         public.wilson_lower(j.up_count, j.down_count) as score
  from public.jokes j
  join public.categories c on c.id = j.category_id
  where j.created_at <= now();   -- vorgeplante Witze erscheinen erst an ihrem Tag

-- ───────────────────────── Lesen ─────────────────────────

-- Ranking: day = letzte 24 h, week = letzte 7 Tage, all = ab 20 Stimmen
create function public.get_ranking(p_device uuid, p_range text, p_category text default null,
                                   p_limit int default 30, p_offset int default 0)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value
  from public.joke_feed f
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  where f.status = 'visible'
    and (p_category is null or f.category_slug = p_category)
    and case p_range
          when 'day'  then f.created_at > now() - interval '24 hours'
          when 'week' then f.created_at > now() - interval '7 days'
          else f.up_count + f.down_count >= 20
        end
  order by f.score desc, f.up_count + f.down_count desc, f.created_at desc
  limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0)
$$;

create function public.get_joke(p_device uuid, p_id bigint)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         (f.author_device = p_device or f.author_user = auth.uid()) is true, v.value
  from public.joke_feed f
  left join public.votes v on v.joke_id = f.id and v.device_id = p_device
  where f.id = p_id and f.status = 'visible'
$$;

-- Swipe-Modus: noch nicht bewertete Witze, zuerst die mit unter 20 Stimmen
create function public.get_unrated(p_device uuid, p_exclude bigint[] default '{}', p_limit int default 10)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql volatile security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         false, null::smallint
  from public.joke_feed f
  where f.status = 'visible'
    and f.author_device <> p_device
    and (auth.uid() is null or f.author_user is null or f.author_user <> auth.uid())
    and not (f.id = any(coalesce(p_exclude, '{}')))
    and not exists (select 1 from public.votes v where v.joke_id = f.id and v.device_id = p_device)
  order by (f.up_count + f.down_count >= 20), (f.created_at < now() - interval '7 days'), random()
  limit least(greatest(p_limit, 1), 30)
$$;

-- Gibt es den Witz schon? (Live-Hinweis beim Tippen)
create function public.find_similar(p_body text)
returns table (id bigint, body text, match real)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.body, similarity(j.body_norm, public.normalize_joke(p_body))
  from public.jokes j
  where j.status = 'visible'
    and j.body_norm % public.normalize_joke(p_body)
    and similarity(j.body_norm, public.normalize_joke(p_body)) >= 0.6
  order by 3 desc
  limit 1
$$;

-- ───────────────────────── Schreiben ─────────────────────────

-- Abstimmen. p_value: 1 = Like, -1 = Dislike, 0 = Stimme zurücknehmen
create function public.cast_vote(p_device uuid, p_joke bigint, p_value int)
returns table (up_count int, down_count int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  h        text := public.client_ip_hash();
  v_author uuid;
  v_user   uuid;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  if p_value is null or p_value not in (-1, 0, 1) then raise exception 'invalid_value'; end if;

  select j.author_device, j.author_user into v_author, v_user from public.jokes j where j.id = p_joke and j.status = 'visible';
  if not found then raise exception 'joke_not_found'; end if;
  if v_author = p_device or (v_user is not null and v_user = auth.uid()) then raise exception 'own_joke'; end if;

  if p_value = 0 then
    delete from public.votes v where v.joke_id = p_joke and v.device_id = p_device;
  else
    if not exists (select 1 from public.votes v where v.joke_id = p_joke and v.device_id = p_device) then
      -- max. 300 neue Stimmen pro Stunde und IP
      if (select count(*) from public.votes v where v.ip_hash = h and v.created_at > now() - interval '1 hour') >= 300 then
        raise exception 'rate_limited';
      end if;
      -- max. 5 Stimmen pro Witz und IP (WG, Familie, Firmennetz); bremst Mehrfach-Votes per Inkognito-Fenster
      if (select count(*) from public.votes v where v.joke_id = p_joke and v.ip_hash = h) >= 5 then
        raise exception 'ip_limit';
      end if;
    end if;
    insert into public.votes (joke_id, device_id, ip_hash, value)
    values (p_joke, p_device, h, p_value)
    on conflict (joke_id, device_id) do update set value = excluded.value;
  end if;

  update public.jokes j set
    up_count   = (select count(*) from public.votes v where v.joke_id = p_joke and v.value = 1),
    down_count = (select count(*) from public.votes v where v.joke_id = p_joke and v.value = -1)
  where j.id = p_joke;

  return query select j.up_count, j.down_count from public.jokes j where j.id = p_joke;
end $$;

-- Witz posten: NUR mit Konto. Der Name kommt aus dem Profil. Gibt die neue ID zurück.
create function public.post_joke(p_device uuid, p_category text, p_body text)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  h      text := public.client_ip_hash();
  v_user uuid := auth.uid();
  v_name text;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_cat  int;
  v_dup  bigint;
  v_id   bigint;
begin
  if v_user is null then raise exception 'not_logged_in'; end if;
  select p.username into v_name from public.profiles p where p.id = v_user;
  if v_name is null then raise exception 'not_logged_in'; end if;
  if p_device is null then raise exception 'invalid_device'; end if;
  if char_length(v_body) not between 10 and 500 then raise exception 'invalid_body'; end if;

  select c.id into v_cat from public.categories c where c.slug = p_category;
  if v_cat is null then raise exception 'invalid_category'; end if;

  -- max. 10 Witze pro Konto und 20 pro IP in 24 Stunden
  if (select count(*) from public.jokes j where j.author_user = v_user and j.created_at > now() - interval '24 hours') >= 10
     or (select count(*) from public.jokes j where j.ip_hash = h and j.created_at > now() - interval '24 hours') >= 20 then
    raise exception 'post_limit';
  end if;

  -- Duplikat: ab 60 % Ähnlichkeit mit einem sichtbaren Witz
  v_norm := public.normalize_joke(v_body);
  select j.id into v_dup
  from public.jokes j
  where j.status = 'visible' and j.body_norm % v_norm and similarity(j.body_norm, v_norm) >= 0.6
  order by similarity(j.body_norm, v_norm) desc
  limit 1;
  if v_dup is not null then
    raise exception 'duplicate' using detail = v_dup::text;
  end if;

  insert into public.jokes (category_id, body, author_name, author_device, author_user, ip_hash)
  values (v_cat, v_body, v_name, p_device, v_user, h)
  returning jokes.id into v_id;
  return v_id;
end $$;

-- Ist ein Benutzername noch frei? (für die Registrierung)
create function public.username_available(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select trim(coalesce(p_name, '')) ~ '^[A-Za-z0-9_.äöüÄÖÜß]{3,20}$'
     and not exists (select 1 from public.profiles p where lower(p.username) = lower(trim(p_name)))
$$;

-- Eigenes Profil (nach dem Anmelden)
create function public.my_profile() returns table (username text)
language sql stable security definer set search_path = public as $$
  select p.username from public.profiles p where p.id = auth.uid()
$$;

-- Melden. Ab 3 Meldungen von verschiedenen Anschlüssen ausgeblendet,
-- nach einer Freigabe durch die Moderation erst ab 10.
create function public.report_joke(p_device uuid, p_joke bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare
  h     text := public.client_ip_hash();
  v_cnt int;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  if not exists (select 1 from public.jokes j where j.id = p_joke and j.status = 'visible') then
    raise exception 'joke_not_found';
  end if;

  insert into public.reports (joke_id, device_id, ip_hash) values (p_joke, p_device, h)
  on conflict do nothing;

  select count(distinct coalesce(r.ip_hash, r.device_id::text)) into v_cnt
  from public.reports r where r.joke_id = p_joke;

  update public.jokes j set
    report_count = v_cnt,
    status = case
      when j.status = 'visible' and v_cnt >= (case when j.reviewed_at is null then 3 else 10 end) then 'hidden'
      else j.status end
  where j.id = p_joke;
end $$;

-- ───────────────────────── Moderation (per Admin-Schlüssel) ─────────────────────────

-- Nur im SQL Editor aufrufbar (siehe ganz unten)
create function public.set_admin_key(p_key text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if char_length(coalesce(p_key, '')) < 12 then
    raise exception 'Der Admin-Schlüssel braucht mindestens 12 Zeichen.';
  end if;
  insert into public.settings (key, value) values ('admin_key', crypt(p_key, gen_salt('bf')))
  on conflict (key) do update set value = excluded.value;
end $$;

create function public.admin_check(p_key text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select char_length(coalesce(p_key, '')) >= 12
     and coalesce((select s.value = crypt(p_key, s.value) from public.settings s where s.key = 'admin_key'), false)
$$;

-- p_view: 'gemeldet' (ausgeblendet oder gemeldet) oder 'neu' (neueste sichtbare)
create function public.admin_list(p_key text, p_view text)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, report_count int, status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  if p_view = 'neu' then
    return query
      select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.report_count, f.status
      from public.joke_feed f where f.status = 'visible'
      order by f.created_at desc limit 50;
  else
    return query
      select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.report_count, f.status
      from public.joke_feed f
      where f.status = 'hidden' or (f.status = 'visible' and f.report_count > 0)
      order by f.status asc, f.report_count desc, f.created_at desc limit 100;
  end if;
end $$;

-- p_status: 'visible' = freigeben (Meldungen verwerfen), 'removed' = entfernen
create function public.admin_set_status(p_key text, p_joke bigint, p_status text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_key) then raise exception 'not_admin'; end if;
  if p_status = 'visible' then
    delete from public.reports r where r.joke_id = p_joke;
    update public.jokes j set status = 'visible', report_count = 0, reviewed_at = now() where j.id = p_joke;
  elsif p_status = 'removed' then
    update public.jokes j set status = 'removed', reviewed_at = now() where j.id = p_joke;
  else
    raise exception 'invalid_status';
  end if;
end $$;

-- ───────────────────────── Rechte ─────────────────────────
-- Besucher (anon) dürfen keine Tabelle direkt lesen oder schreiben, nur die Funktionen aufrufen.

alter table public.settings   enable row level security;
alter table public.profiles   enable row level security;
alter table public.categories enable row level security;
alter table public.jokes      enable row level security;
alter table public.votes      enable row level security;
alter table public.reports    enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant select on public.categories to anon, authenticated;
create policy "Kategorien sind öffentlich" on public.categories for select using (true);

grant execute on function
  public.get_ranking(uuid, text, text, int, int),
  public.get_joke(uuid, bigint),
  public.get_unrated(uuid, bigint[], int),
  public.find_similar(text),
  public.cast_vote(uuid, bigint, int),
  public.post_joke(uuid, text, text),
  public.username_available(text),
  public.my_profile(),
  public.report_joke(uuid, bigint),
  public.admin_check(text),
  public.admin_list(text, text),
  public.admin_set_status(text, bigint, text)
to anon, authenticated;

-- ───────────────────────── Startdaten ─────────────────────────

insert into public.categories (slug, name, position) values
  ('flachwitze', 'Flachwitze', 1),
  ('wortspiele', 'Wortspiele', 2),
  ('tiere',      'Tiere',      3),
  ('schule',     'Schule',     4),
  ('buero',      'Büro',       5),
  ('nerd',       'Nerd',       6),
  ('schwarz',    'Schwarzer Humor', 7),
  ('einzeiler',  'Einzeiler',  8);

-- 360 Startwitze von der „Lachwerk“-Redaktion, vorgeplant über 35 Tage:
-- Rund 5 Tage liegen in der Vergangenheit, danach erscheinen jeden Tag etwa 10 neue Witze.
-- So ist „Heute“ auch ohne neue Beiträge von Besuchern einen Monat lang gefüllt.
-- Bewusst ohne erfundene Stimmen: Die ersten Besucher bewerten sie im Swipe-Modus.
insert into public.jokes (category_id, body, author_name, author_device, created_at)
select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
       date_trunc('day', now()) - interval '5 days'
         + ((row_number() over ()) * 3 % 35) * interval '1 day'
         + random() * interval '20 hours'
from (values
  ('flachwitze', 'Was ist grün und klopft an die Tür?
Ein Klopfsalat.'),
  ('flachwitze', 'Was sitzt auf dem Baum und schreit „Aha“?
Ein Uhu mit Sprachfehler.'),
  ('flachwitze', 'Was ist rot und schlecht für die Zähne?
Ein Ziegelstein.'),
  ('flachwitze', 'Was ist braun, klebrig und läuft durch die Wüste?
Ein Karamel.'),
  ('flachwitze', 'Was macht ein Clown im Büro?
Faxen.'),
  ('flachwitze', 'Was ist orange und wandert durch die Berge?
Eine Wanderine.'),
  ('flachwitze', 'Was liegt am Strand und spricht undeutlich?
Eine Nuschel.'),
  ('flachwitze', 'Was ist gelb und kann nicht schwimmen?
Ein Bagger. Er hat nur einen Arm.'),
  ('flachwitze', 'Was ist ein Cowboy ohne Pferd?
Ein Sattelschlepper.'),
  ('flachwitze', 'Was ist schwarz-weiß und hüpft auf und ab?
Ein Pinguin auf dem Trampolin.'),
  ('flachwitze', 'Was ist grün und rennt durch den Wald?
Ein Rudel Gurken.'),
  ('flachwitze', 'Was ist braun und sitzt hinter Gittern?
Eine Knastanie.'),
  ('flachwitze', 'Was steht auf dem Grabstein eines Mathematikers?
„Damit hat er nicht gerechnet.“'),
  ('flachwitze', 'Was ist weiß und springt über die Wiese?
Ein Springquark.'),
  ('flachwitze', 'Was ist blau und riecht nach roter Farbe?
Blaue Farbe.'),
  ('flachwitze', 'Was ist rund, lila und fährt durch die Stadt?
Eine Brombeere mit Führerschein.'),
  ('flachwitze', 'Was sagt ein großer Stift zu einem kleinen Stift?
„Wachs mal, Stift!“'),
  ('flachwitze', 'Was sagt der Mond zur Sonne?
„So groß und darfst nachts immer noch nicht raus.“'),
  ('flachwitze', 'Was ist braun und schwimmt unter Wasser?
Ein U-Brot.'),
  ('flachwitze', 'Was ist die Lieblingsmusik von Steinen?
Rock.'),
  ('flachwitze', 'Was macht ein Zahnarzt ohne Patienten?
Er bohrt in der Nase.'),
  ('flachwitze', 'Was ist gelb, krumm und schwimmt auf dem See?
Eine Schwanane.'),
  ('flachwitze', 'Was ist grau, steht auf der Wiese und telefoniert?
Ein Telefant.'),
  ('flachwitze', 'Was ist rot und sitzt auf dem Klo?
Eine Klomate.'),
  ('flachwitze', 'Was ist gelb und schießt?
Eine Banone.'),
  ('flachwitze', 'Was hat vier Räder und fliegt?
Ein Müllwagen.'),
  ('flachwitze', 'Was ist grau und kann nicht schwimmen?
Eine Wand.'),
  ('flachwitze', 'Was ist rot und fährt ständig rauf und runter?
Eine Tomate im Aufzug.'),
  ('flachwitze', 'Was ist grün und hat Räder?
Gras. Das mit den Rädern war gelogen.'),
  ('flachwitze', 'Was macht ein Keks im Krankenhaus?
Er fühlt sich ganz krümelig.'),
  ('flachwitze', 'Was ist braun, haarig und trägt eine Sonnenbrille?
Eine Kokosnuss im Urlaub.'),
  ('flachwitze', 'Was ist schwarz, weiß und rot?
Ein Zebra mit Sonnenbrand.'),
  ('flachwitze', 'Wie nennt man einen Bären ohne Zähne?
Gummibär.'),
  ('flachwitze', 'Was ist braun und ruft „Hilfe“?
Ein Toast, der zu lange im Toaster war.'),
  ('flachwitze', 'Was ist gelb und liegt im Bett?
Eine Banane mit Fieber.'),
  ('flachwitze', 'Wohin geht eine Wolke, wenn es sie juckt?
Zum Wolkenkratzer.'),
  ('flachwitze', 'Was macht Hefeteig im Fitnessstudio?
Er geht auf.'),
  ('flachwitze', 'Was ist ein Fisch ohne Augen?
Ein Fsch.'),
  ('flachwitze', 'Was ist rot und sitzt in der Ecke?
Eine schüchterne Tomate.'),
  ('flachwitze', 'Was ist klein, grün und dreieckig?
Ein kleines grünes Dreieck.'),
  ('flachwitze', 'Was ist cooler als ein Schneemann?
Ein Schneemann mit Sonnenbrille.'),
  ('flachwitze', 'Was ist weiß und rollt den Berg hinauf?
Eine Lawine mit Heimweh.'),
  ('flachwitze', 'Was ist der Unterschied zwischen einem Bäcker und einem Teppich?
Der Bäcker muss um vier Uhr aufstehen, der Teppich kann liegen bleiben.'),
  ('flachwitze', 'Was ist der Unterschied zwischen einem Keks und einem Elefanten?
Einen Keks kann man in den Kakao tunken.'),
  ('flachwitze', 'Sagt die eine Wand zur anderen:
„Wir treffen uns an der Ecke.“'),
  ('flachwitze', 'Zwei Tomaten gehen über die Straße. Die eine wird überfahren.
Sagt die andere: „Komm, Ketchup!“'),
  ('flachwitze', 'Kommt ein Pferd in die Bar. Fragt der Barkeeper:
„Warum so ein langes Gesicht?“'),
  ('flachwitze', 'Kommt ein Skelett in die Bar und bestellt:
„Ein Bier und einen Wischmopp, bitte.“'),
  ('flachwitze', '„Herr Doktor, ich fühle mich wie ein Vorhang.“
„Jetzt reißen Sie sich mal zusammen!“'),
  ('flachwitze', '„Herr Doktor, alle ignorieren mich.“
„Der Nächste, bitte!“'),
  ('flachwitze', '„Herr Ober, was macht die Fliege in meiner Suppe?“
„Sieht nach Rückenschwimmen aus.“'),
  ('flachwitze', '„Herr Ober, der Teller ist ja ganz nass!“
„Das ist die Suppe.“'),
  ('flachwitze', 'Was ist rot und flüstert?
Eine Tomate mit Halsschmerzen.'),
  ('flachwitze', 'Was ist braun und dreht sich im Kreis?
Ein Kaffee, der umgerührt wird.'),
  ('flachwitze', 'Was essen Boxer am liebsten?
Schlagsahne.'),
  ('flachwitze', 'Was sitzt auf dem Dach und raucht?
Ein Schornstein.'),
  ('flachwitze', 'Was hängt an der Wand und macht „Kcat-kcit“?
Eine Uhr, die rückwärts läuft.'),
  ('flachwitze', 'Was machen zwei wütende Schafe?
Sie kriegen sich in die Wolle.'),
  ('flachwitze', 'Was macht ein Kaktus auf einer Party?
Er sticht aus der Menge heraus.'),
  ('flachwitze', 'Was essen Gespenster am liebsten?
Spukhetti.'),
  ('wortspiele', 'Was macht ein Pirat am Computer?
Er drückt die Enter-Taste.'),
  ('wortspiele', 'Wie nennt man einen Bumerang, der nicht zurückkommt?
Stock.'),
  ('wortspiele', 'Was ist ein Keks unter einem Baum?
Ein schattiges Plätzchen.'),
  ('wortspiele', 'Treffen sich zwei Magnete. Sagt der eine:
„Was soll ich heute bloß anziehen?“'),
  ('wortspiele', 'Was sagt ein Gen, wenn es ein anderes trifft?
„Hallo, Gen!“'),
  ('wortspiele', 'Was ist ein Hai mit Kopfhörern?
Ein Hai-Fi.'),
  ('wortspiele', 'Warum gehen Elektriker so gern ins Theater?
Wegen der Spannung.'),
  ('wortspiele', 'Welcher Bus hat den Atlantik überquert?
Kolumbus.'),
  ('wortspiele', 'Wo wohnen Katzen?
Im Miezhaus.'),
  ('wortspiele', 'Was sagt der Ozean zum Strand?
Nichts. Er winkt nur.'),
  ('wortspiele', 'Was macht ein Mathematiker im Garten?
Wurzeln ziehen.'),
  ('wortspiele', 'Was ist ein Schneemann mit Sonnenbrand?
Eine Pfütze.'),
  ('wortspiele', 'Warum können Geister so schlecht lügen?
Man durchschaut sie sofort.'),
  ('wortspiele', 'Warum sind Fische so schlau?
Weil sie in Schulen leben.'),
  ('wortspiele', 'Wie heißt der Bruder von Elvis?
Zwölvis.'),
  ('wortspiele', 'Wie nennt man einen Löwen, der Witze erzählt?
Einen Brüller.'),
  ('wortspiele', 'Warum ist der Kalender so nervös?
Seine Tage sind gezählt.'),
  ('wortspiele', 'Was sagt ein Fisch, der gegen eine Mauer schwimmt?
„Damm!“'),
  ('wortspiele', 'Was sagt der Kühlschrank zur Milch?
„Bleib cool.“'),
  ('wortspiele', 'Warum wurde die Tomate rot?
Sie hat das Salatdressing gesehen.'),
  ('wortspiele', 'Was macht ein Uhrmacher im Urlaub?
Er nimmt sich Zeit.'),
  ('wortspiele', 'Warum sind Bananen krumm?
Weil niemand in den Urwald zog und die Banane gerade bog.'),
  ('wortspiele', 'Was trinken Gespenster am liebsten?
Buuuh-ttermilch.'),
  ('wortspiele', 'Was ist ein Pferd, das Bücher schreibt?
Ein Hengstseller.'),
  ('wortspiele', 'Was ist ein Vampir, der Gemüse isst?
Ein Blutorangen-Fan.'),
  ('wortspiele', 'Warum gewinnt der Pilz jedes Rennen?
Er ist ein Champignon.'),
  ('wortspiele', 'Wie heißt ein Spanier ohne Auto?
Carlos.'),
  ('wortspiele', 'Was sagt ein Spiegel zum anderen?
„Wir sollten uns mal reflektieren.“'),
  ('wortspiele', 'Wie nennt man einen Vogel mit Schulden?
Pleitegeier.'),
  ('wortspiele', 'Warum ging das Buch zum Arzt?
Es hatte Rückenschmerzen.'),
  ('wortspiele', 'Warum war der Baum beim Psychologen?
Er hatte tief verwurzelte Probleme.'),
  ('wortspiele', 'Was ist ein Hund mit Fieber?
Ein Hot Dog.'),
  ('wortspiele', 'Was essen Schauspieler am liebsten?
Rollmops.'),
  ('wortspiele', 'Was essen Autos am liebsten?
Parkplätzchen.'),
  ('wortspiele', 'Welches Instrument spielt ein Fisch?
Kontrabarsch.'),
  ('wortspiele', 'Warum gehen Bäcker nie pleite?
Sie verdienen sich ihr Brot.'),
  ('wortspiele', 'Was macht ein Huhn mit seinem Geld?
Es legt es an.'),
  ('wortspiele', 'Warum ist der Backofen so beliebt?
Er ist einfach warmherzig.'),
  ('wortspiele', 'Ich wollte einen Witz über einen Bleistift erzählen.
Aber er hatte keine Spitze.'),
  ('wortspiele', 'Ich kenne einen Witz über Bauarbeiter.
Aber da wird noch dran gearbeitet.'),
  ('wortspiele', 'Ich würde euch einen Witz über Zeitreisen erzählen.
Aber ihr habt ihn gestern schon nicht gemocht.'),
  ('wortspiele', 'Ich kenne einen Witz über Pizza.
Der ist aber ziemlich käsig.'),
  ('wortspiele', 'Was sagt der große Vulkan zum kleinen Vulkan?
„Ich lava dich.“'),
  ('wortspiele', 'Was sagt die Null zur Acht?
„Schicker Gürtel!“'),
  ('wortspiele', 'Was macht eine Kerze, wenn sie traurig ist?
Sie lässt den Docht hängen.'),
  ('wortspiele', 'Warum gehen Ameisen nicht in die Kirche?
Sie sind In-Sekten.'),
  ('wortspiele', 'Welche Schlange ist die gemeinste?
Die Warteschlange.'),
  ('wortspiele', 'Welche Bank hat kein Geld?
Die Parkbank.'),
  ('wortspiele', 'Welche Hose hat keine Beine?
Die Wasserhose.'),
  ('wortspiele', 'Welcher Stuhl hat keine Beine?
Der Stuhlgang.'),
  ('wortspiele', 'Warum ist der Himmel so hoch?
Damit sich die Vögel nicht den Kopf stoßen.'),
  ('wortspiele', 'Welche Musik hören Luftballons?
Pop.'),
  ('wortspiele', 'Welcher Ball ist nicht rund?
Der Maskenball.'),
  ('wortspiele', 'Welches Schiff hat keine Segel?
Das Kirchenschiff.'),
  ('wortspiele', 'Welcher Hahn kräht nie?
Der Wasserhahn.'),
  ('wortspiele', 'Welche Mutter hat keine Kinder?
Die Schraubenmutter.'),
  ('wortspiele', 'Welcher Zahn beißt nicht?
Der Löwenzahn.'),
  ('wortspiele', 'Welcher Bart wächst nie?
Der Schlüsselbart.'),
  ('wortspiele', 'Welche Birne kann man nicht essen?
Die Glühbirne.'),
  ('wortspiele', 'Welcher Kater hat kein Fell?
Der nach der Party.'),
  ('tiere', 'Treffen sich zwei Schnecken. Fragt die eine: „Warum so schnell unterwegs?“
„Ich hab mein Haus vergessen.“'),
  ('tiere', 'Was macht ein Hai im Computer?
Er surft im Netz.'),
  ('tiere', 'Sagt die eine Kuh: „Muh.“
Sagt die andere: „Das wollte ich auch gerade sagen.“'),
  ('tiere', 'Was ist der Lieblingsfilm von Kühen?
Muhlan Rouge.'),
  ('tiere', 'Ein Pinguin läuft durch die Wüste und denkt:
„Hier muss es aber glatt sein, so viel wie hier gestreut wurde.“'),
  ('tiere', 'Was sagt ein Hamster nach dem Training?
„Ich dreh am Rad.“'),
  ('tiere', 'Warum haben Giraffen so lange Hälse?
Weil ihre Füße so stinken.'),
  ('tiere', 'Wie nennt man ein Schaf ohne Beine?
Eine Wolke.'),
  ('tiere', 'Warum sind Frösche so glücklich?
Sie fressen einfach alles, was sie nervt.'),
  ('tiere', 'Zwei Kühe auf der Weide. Die eine: „Hast du keine Angst vor Rinderwahnsinn?“
Die andere: „Nö, ich bin ein Hubschrauber.“'),
  ('tiere', 'Was sagt die Schnecke, die auf einer Schildkröte reitet?
„Huiii!“'),
  ('tiere', 'Warum ging das Huhn über die Straße?
Um auf die andere Seite zu kommen.'),
  ('tiere', 'Wie umarmen sich Igel?
Ganz vorsichtig.'),
  ('tiere', 'Warum schwimmen Fische nicht auf dem Rücken?
Sonst bekommen sie einen Sonnenbrand am Bauch.'),
  ('tiere', 'Was bestellt ein Pferd im Café?
Einen Hafer-Latte.'),
  ('tiere', 'Fragt der Kunde in der Zoohandlung: „Kann der Papagei sprechen?“
Sagt der Papagei: „Kannst du fliegen?“'),
  ('tiere', 'Was ist ein Kater im Fitnessstudio?
Ein Muskelkater.'),
  ('tiere', 'Welches Tier ist das stärkste?
Die Schnecke. Sie trägt ihr ganzes Haus.'),
  ('tiere', 'Wer sitzt im Dschungel und schummelt?
Mogli.'),
  ('tiere', 'Was hat vier Beine und kann fliegen?
Zwei Vögel.'),
  ('tiere', 'Warum legen Hühner Eier?
Wenn sie sie werfen würden, gingen sie kaputt.'),
  ('tiere', 'Was ist schlimmer als ein Wurm im Apfel?
Ein halber Wurm im Apfel.'),
  ('tiere', 'Treffen sich zwei Hunde. Sagt der eine: „Wau.“ Sagt der andere: „Miau.“
„Wieso miau?“ – „Ich lerne Fremdsprachen.“'),
  ('tiere', 'Was ist braun und schaut durchs Schlüsselloch?
Ein Spannferkel.'),
  ('tiere', 'Warum können Kühe nicht fliegen?
Weil sie kein Muh-tor haben.'),
  ('tiere', 'Wie bekommt man einen Elefanten in den Kühlschrank?
Tür auf, Elefant rein, Tür zu.
Und eine Giraffe? Tür auf, Elefant raus, Giraffe rein, Tür zu.'),
  ('tiere', 'Treffen sich zwei Fische. Sagt der eine: „Hi!“
Sagt der andere: „Wo?!“'),
  ('tiere', 'Warum fliegen Vögel im Winter in den Süden?
Weil es zu Fuß zu weit ist.'),
  ('tiere', 'Welches Tier springt höher als ein Haus?
Jedes. Häuser können nicht springen.'),
  ('tiere', 'Zwei Mäuse sehen eine Fledermaus.
Sagt die eine: „Schau mal, ein Engel!“'),
  ('tiere', 'Warum sitzt die Katze so gern am Computer?
Wegen der Maus.'),
  ('tiere', 'Was machen Kühe in der Disco?
Milchshakes.'),
  ('tiere', 'Wohin gehen Kühe am Wochenende?
Ins Muuuuseum.'),
  ('tiere', 'Zwei Schafe auf der Weide. Sagt das eine: „Mäh.“
Sagt das andere: „Mäh doch selber!“'),
  ('tiere', 'Warum hat der Tausendfüßler das Fußballspiel verpasst?
Bis er alle Schuhe anhatte, war das Spiel vorbei.'),
  ('tiere', 'Ein Elefant und eine Maus laufen über eine Holzbrücke.
Sagt die Maus: „Hörst du, wie wir trampeln?“'),
  ('tiere', 'Wie nennt man eine Kuh, die Gras frisst?
Rasenmäher.'),
  ('tiere', 'Zwei Pinguine auf einer Eisscholle. Sagt der eine: „Du siehst aus, als würdest du einen Frack tragen.“
„Wer sagt denn, dass ich keinen trage?“'),
  ('tiere', 'Zwei Flöhe kommen aus dem Kino. Fragt der eine:
„Gehen wir zu Fuß oder nehmen wir einen Hund?“'),
  ('tiere', 'Warum haben Elefanten rote Augen?
Damit sie sich im Kirschbaum verstecken können.
Hast du schon mal einen Elefanten im Kirschbaum gesehen? Siehst du, es funktioniert.'),
  ('tiere', 'Was war zuerst da, das Huhn oder das Ei?
Ich habe beide online bestellt. Das Huhn kam zuerst.'),
  ('tiere', 'Was sagt der Hahn, wenn er verschlafen hat?
„Kikeri-oh nein!“'),
  ('tiere', 'Was sagt der Wal, wenn er sich nicht entscheiden kann?
„Ich hab die Qual der Wal.“'),
  ('tiere', 'Wie nennt man ein Faultier, das Sport macht?
Ein Wunder.'),
  ('tiere', 'Was sagt das Faultier am Montag?
Nichts. Es schläft bis Mittwoch.'),
  ('tiere', 'Warum sind Flamingos rosa?
Sie haben vergessen, sich einzucremen.'),
  ('tiere', 'Kommt ein Hase in die Bäckerei: „Hattu Möhrenkuchen?“ – „Nein.“ Am nächsten Tag: „Hattu Möhrenkuchen?“ – „Nein!“
Am dritten Tag hat der Bäcker extra einen gebacken. „Hattu Möhrenkuchen?“ – „Ja!“ – „Muss ja eklig schmecken.“'),
  ('tiere', 'Warum geht der Igel in den Blumenladen?
Er besucht seine Verwandtschaft, die Kakteen.'),
  ('tiere', 'Warum fressen Eisbären keine Pinguine?
Sie kriegen die Verpackung nicht auf.'),
  ('tiere', 'Sagt die Raupe zum Schmetterling:
„Du hast dich aber verändert.“'),
  ('tiere', 'Wie nennt man einen Hund, der zaubern kann?
Labrakadabrador.'),
  ('tiere', 'Warum tragen Kühe Glocken?
Weil ihre Hörner nicht funktionieren.'),
  ('tiere', 'Welchen Sport machen Bienen am liebsten?
Summba.'),
  ('tiere', 'Welcher Fisch ist immer gut gelaunt?
Der Lachs.'),
  ('tiere', 'Woran erkennt man, dass ein Elefant im Kühlschrank war?
An den Fußspuren in der Butter.'),
  ('tiere', 'Warum haben Störche so lange Beine?
Damit ihre Füße bis zum Boden reichen.'),
  ('tiere', 'Warum fliegen Eulen nur nachts?
Tagsüber ist zu viel Verkehr.'),
  ('tiere', 'Was zählen Schafe, wenn sie nicht einschlafen können?
Menschen.'),
  ('tiere', 'Zwei Goldfische im Glas. Fragt der eine: „Glaubst du an Gott?“
„Natürlich. Wer wechselt denn sonst das Wasser?“'),
  ('tiere', 'Fragt eine Schlange die andere: „Sind wir eigentlich giftig?“ – „Wieso?“
„Ich hab mir gerade auf die Zunge gebissen.“'),
  ('schule', 'Lehrerin: „Nenne mir fünf Tiere aus Afrika.“
Fritzchen: „Vier Löwen und ein Elefant.“'),
  ('schule', '„Fritzchen, was ist die Mehrzahl von Baum?“
„Wald.“'),
  ('schule', 'Warum ist das Mathebuch traurig?
Es hat zu viele Probleme.'),
  ('schule', '„Fritzchen, warum kommst du zu spät?“
„Auf dem Schild stand doch: Schule – bitte langsam fahren!“'),
  ('schule', 'Lehrerin: „Wenn ich sage: Ich war schön – welche Zeit ist das?“
Fritzchen: „Eindeutig Vergangenheit.“'),
  ('schule', '„Warum hast du eine Sechs in Mathe?“ – „Die Lehrerin hat gefragt, was 3 mal 4 ist. Ich habe 12 gesagt. Dann hat sie gefragt, was 4 mal 3 ist.“
„Und wo ist da der Unterschied?“ – „Genau das habe ich auch gesagt.“'),
  ('schule', 'Lehrer: „Was ist flüssiger als Wasser?“
Schüler: „Hausaufgaben. Die sind überflüssig.“'),
  ('schule', 'Lehrer: „Nenne mir drei Dinge, in denen Milch steckt.“
„Butter, Käse und eine Kuh.“'),
  ('schule', 'Schüler: „Kann man für etwas bestraft werden, das man nicht gemacht hat?“ – Lehrer: „Natürlich nicht.“
Schüler: „Gut. Ich habe meine Hausaufgaben nicht gemacht.“'),
  ('schule', 'Lehrer: „Du hast fünf Äpfel, und ich nehme dir zwei weg. Was hast du dann?“
„Streit.“'),
  ('schule', 'Warum nehmen manche Schüler eine Leiter mit in die Schule?
Sie wollen auf die höhere Schule.'),
  ('schule', 'Lehrerin: „Was passiert, wenn man einen Stein ins Rote Meer wirft?“
Fritzchen: „Er wird nass.“'),
  ('schule', 'Vater: „Wie lief die Mathearbeit?“ – „Fast alles richtig.“ – „Und was war falsch?“
„Die Antworten.“'),
  ('schule', '„Fritzchen, warum schreibst du so langsam?“
„Der Brief ist für Opa, und der kann nicht so schnell lesen.“'),
  ('schule', 'Erdkundelehrer: „Was weißt du über das Tote Meer?“
„Ich wusste nicht mal, dass es krank war.“'),
  ('schule', 'Lehrerin: „Wie viele Sekunden hat ein Jahr?“
Fritzchen: „Zwölf. Zweiter Januar, zweiter Februar …“'),
  ('schule', 'Lehrerin: „Fritzchen, du hast genau die gleichen Fehler wie dein Nachbar.“
„Wir haben ja auch die gleiche Lehrerin.“'),
  ('schule', 'Mutter: „Was habt ihr heute in der Schule gelernt?“
„Offenbar nicht genug. Wir müssen morgen wieder hin.“'),
  ('schule', 'Lehrer: „Was ist schneller, Licht oder Schall?“
Schüler: „Licht. Beim Fernseher kommt erst das Bild und dann der Ton.“'),
  ('schule', '„Fritzchen, was ist 7 mal 7?“ – „49.“ – „Sehr gut!“
„Sehr gut? Das ist perfekt!“'),
  ('schule', 'Warum steht der Musiklehrer vor der verschlossenen Tür?
Er hat seinen Notenschlüssel verloren.'),
  ('schule', 'Lehrerin: „Bilde einen Satz mit ‚obwohl‘.“
Fritzchen: „Ob wohl bald Pause ist?“'),
  ('schule', 'Biolehrer: „Was hat der Mensch, was Tiere nicht haben?“
„Hausaufgaben.“'),
  ('schule', '„Papa, ich war heute der Einzige, der sich gemeldet hat!“ – „Super! Was war die Frage?“
„Wer hat seine Hausaufgaben nicht gemacht?“'),
  ('schule', 'Lehrer: „Wie nennt man jemanden, der immer redet, auch wenn keiner zuhört?“
Fritzchen: „Lehrer.“'),
  ('schule', 'Lehrer: „Was ist die Hälfte von acht?“
Fritzchen: „Waagerecht null, senkrecht drei.“'),
  ('schule', 'Lehrer: „Ich gehe, du gehst, er geht, wir gehen, ihr geht, sie gehen. Was bedeutet das?“
Fritzchen: „Alle sind weg.“'),
  ('schule', 'Lehrer: „Du hast 10 Euro und bittest deinen Vater um 10 Euro. Wie viel hast du dann?“ – „10 Euro.“ – „Du kannst ja nicht rechnen!“
„Sie kennen meinen Vater nicht.“'),
  ('schule', 'Lehrer: „Deine Hausaufgabe ist genau wie die von Max. Was soll ich daraus schließen?“
Fritzchen: „Dass die von Max auch richtig ist?“'),
  ('schule', 'Lehrerin: „Fritzchen, nenne mir zwei Pronomen.“
Fritzchen: „Wer? Ich?“ – „Richtig!“'),
  ('schule', 'Lehrer: „Was ist der Unterschied zwischen Unwissenheit und Gleichgültigkeit?“
Schüler: „Weiß ich nicht und ist mir egal.“ – „Perfekt!“'),
  ('schule', 'Lehrerin: „Ich sage ein Wort, du sagst das Gegenteil. Groß.“ – „Klein.“ – „Hell.“ – „Dunkel.“ – „Ungefähr.“
„Gefähr.“'),
  ('schule', 'Lehrer: „Wie kann man ein rohes Ei einen Meter tief fallen lassen, ohne dass es kaputtgeht?“
Fritzchen: „Man lässt es aus zwei Metern fallen. Den ersten Meter übersteht es.“'),
  ('schule', 'Physiklehrer: „Körper dehnen sich bei Wärme aus und ziehen sich bei Kälte zusammen. Beispiel?“
Fritzchen: „Die Sommerferien sind lang, die Winterferien kurz.“'),
  ('schule', 'Geschichtslehrer: „Wo wurde die Unabhängigkeitserklärung unterschrieben?“
Fritzchen: „Ganz unten.“'),
  ('schule', 'Erdkundelehrer: „Was liegt zwischen Deutschland und Frankreich?“
Fritzchen: „Das ‚und‘.“'),
  ('schule', 'Mathelehrer: „Ich habe zwei Äpfel in der einen Hand und drei in der anderen. Was habe ich?“
Fritzchen: „Riesige Hände.“'),
  ('schule', 'Lehrer: „Ich frage zum letzten Mal: Wer hat das Fenster kaputt gemacht?“
Fritzchen: „Super, dann müssen wir ja nicht mehr antworten.“'),
  ('schule', 'Lehrer: „Dein Aufsatz über deinen Hund ist Wort für Wort derselbe wie der deines Bruders.“
Fritzchen: „Ist ja auch derselbe Hund.“'),
  ('schule', 'Sportlehrer: „Leg dich hin und strample in der Luft, als würdest du Fahrrad fahren.“ Nach einer Weile hört Fritzchen auf. „Warum hörst du auf?“
„Jetzt geht''s bergab.“'),
  ('schule', 'Lehrerin: „Wie viele Buchstaben hat das Alphabet?“
Fritzchen: „Acht. A, L, P, H, A, B, E, T.“'),
  ('schule', 'Lehrer: „Was ist schneller, Wärme oder Kälte?“
Fritzchen: „Wärme. Kälte kann man sich ja einfangen.“'),
  ('schule', 'Lehrer: „Dein Vater hat dir bei den Hausaufgaben geholfen, oder?“
Fritzchen: „Nein, er hat sie ganz allein gemacht.“'),
  ('schule', '„Papa, kannst du im Dunkeln unterschreiben?“ – „Ich denke schon.“
„Dann mach mal das Licht aus und unterschreib mein Zeugnis.“'),
  ('schule', 'Lehrer: „Welcher Monat hat 28 Tage?“
Fritzchen: „Alle.“'),
  ('schule', 'Lehrerin: „Nenne ein Beispiel für Ruhestörung.“
Fritzchen: „Wenn Sie mich im Unterricht wecken.“'),
  ('schule', '„Was ist dein Lieblingsfach?“
„Die große Pause.“'),
  ('schule', 'Lehrer: „Woher weißt du, dass die Erde rund ist?“
Fritzchen: „Egal wo ich hingehe, am Ende lande ich wieder in der Schule.“'),
  ('schule', 'Lehrer: „Was ist die Mehrzahl von Mann?“ – „Männer.“ – „Und von Kind?“
„Zwillinge.“'),
  ('schule', 'Mutter: „Wie war dein erster Schultag?“
„Erster? Muss ich da etwa noch mal hin?“'),
  ('schule', 'Lehrerin: „Nenne mir ein Säugetier ohne Zähne.“
Fritzchen: „Meinen Opa.“'),
  ('schule', 'Lehrer: „Was ist ein Vakuum?“
Fritzchen: „Ich hab''s im Kopf, komme aber gerade nicht drauf.“'),
  ('schule', '„Mama, ich war heute der Schnellste!“ – „Beim Sport?“
„Nein, beim Nachhausegehen.“'),
  ('schule', 'Lehrerin: „Warum ist dein Aufsatz so nass?“
Fritzchen: „Sie wollten doch einen Fließtext.“'),
  ('schule', 'Mathelehrer: „Ein Drittel von euch ist durch den Test gefallen.“
Fritzchen: „So viele sind wir doch gar nicht!“'),
  ('schule', 'Lehrer: „Wer zuletzt lacht …“
Fritzchen: „… hat den Witz nicht verstanden.“'),
  ('schule', '„Wie war die Klassenfahrt?“
„Super! Der Lehrer hat uns zwei Tage lang nicht gefunden.“'),
  ('schule', 'Lehrerin: „Wer weiß, was Hieroglyphen sind?“
Fritzchen: „Die Schrift von unserem Hausarzt.“'),
  ('schule', 'Biolehrer: „Was hat sechs Beine, ist grün und sitzt auf einem Blatt?“
Fritzchen: „Keine Ahnung, aber es krabbelt Ihnen gerade den Arm hoch.“'),
  ('schule', 'Lehrer: „Wenn du so weitermachst, wirst du nie versetzt!“
Fritzchen: „Auch gut. Dann bleibe ich in Ihrer Klasse.“'),
  ('buero', 'Chef: „Sie kommen jeden Tag zu spät!“
Ich: „Dafür gehe ich auch früher.“'),
  ('buero', 'Meine Kaffeemaschine hat gekündigt.
Sie fühlt sich ausgepresst.'),
  ('buero', 'Chef: „Was ist Ihre größte Schwäche?“ – „Ehrlichkeit.“ – „Das ist doch keine Schwäche!“
„Ihre Meinung ist mir ehrlich gesagt egal.“'),
  ('buero', 'Kollege: „Ich habe mir vorgenommen, ab heute nichts mehr aufzuschieben.“ – „Und?“
„Fange ich morgen an.“'),
  ('buero', '„Wie lange arbeiten Sie schon hier?“
„Seit mir der Chef mit Kündigung gedroht hat.“'),
  ('buero', 'Chef: „Wir müssen Kosten sparen.“
Mitarbeiter: „Dann streichen wir doch die Meetings, in denen wir übers Kostensparen reden.“'),
  ('buero', 'Was ist ein Meeting?
Ein Ort, an dem man Minuten protokolliert und Stunden verliert.'),
  ('buero', 'Mein Chef sagte: „Denken Sie mal außerhalb der Box.“
Jetzt sitze ich auf dem Flur.'),
  ('buero', '„Wo sehen Sie sich in fünf Jahren?“
„Ehrlich gesagt sehe ich schon heute nicht ganz scharf.“'),
  ('buero', '„Was können Sie besonders gut?“ – „Schnell rechnen.“ – „Was ist 37 mal 49?“ – „Zwölf.“ – „Das ist falsch!“
„Aber schnell.“'),
  ('buero', 'Chef: „Ab sofort gibt es Gleitzeit.“
Ich: „Super, dann gleite ich jetzt nach Hause.“'),
  ('buero', 'Montag ist der Tag, an dem der Kaffee härter arbeitet als ich.'),
  ('buero', 'Ich bin nicht faul.
Ich bin im Energiesparmodus.'),
  ('buero', 'Warum kam der Drucker zu spät zur Arbeit?
Papierstau.'),
  ('buero', 'Chef: „Warum waren Sie gestern nicht da?“ – „Mir ging es nicht gut.“ – „Und heute?“
„Auch nicht. Aber zu Hause ist das WLAN schlechter.“'),
  ('buero', 'E-Mail vom Chef: „Kurze Frage.“
Es folgen elf Absätze.'),
  ('buero', '„Mit freundlichen Grüßen“ heißt im Büro übersetzt:
„Ich bin kurz davor zu explodieren.“'),
  ('buero', 'Homeoffice ist, wenn alle Kollegen plötzlich Katzen, Kinder und eine Zimmerpflanze haben, die unbedingt in die Kamera wollen.'),
  ('buero', 'Chef: „Sie sind schon wieder zu spät!“
„Sie haben doch gesagt, ich soll mir Zeit lassen.“'),
  ('buero', 'Was ist die beliebteste Sportart im Büro?
Aufschieben. Geht allein und im Team.'),
  ('buero', 'Personalchefin: „Wir suchen jemanden, der Verantwortung übernimmt.“
Bewerber: „Perfekt. In meinem alten Job war ich für jeden Fehler verantwortlich.“'),
  ('buero', '„Chef, ich brauche mehr Gehalt. Drei Firmen sind hinter mir her.“ – „Welche denn?“
„Strom, Gas und Telefon.“'),
  ('buero', 'Ich habe mein Passwort in „falsch“ geändert.
Wenn ich es vergesse, sagt der Computer: „Ihr Passwort ist falsch.“'),
  ('buero', 'Ich arbeite super unter Druck.
Deshalb fange ich immer erst am letzten Tag an.'),
  ('buero', 'Chef: „Warum tragen Sie zwei verschiedene Socken?“
„Keine Ahnung, ich habe zu Hause noch so ein Paar.“'),
  ('buero', 'Bewerbungsgespräch: „Haben Sie Erfahrung mit Teamarbeit?“
„Ja, ich habe schon oft andere für mich arbeiten lassen.“'),
  ('buero', '„Was sind Ihre Stärken?“ – „Ich bin sehr anpassungsfähig.“ – „Und Ihre Schwächen?“
„Welche hätten Sie denn gern?“'),
  ('buero', 'Chef: „Warum kommen Sie zu spät?“
„Ich habe von der Arbeit geträumt und wollte das Projekt noch fertig machen.“'),
  ('buero', '„Wie viele Leute arbeiten in Ihrer Firma?“
„Ungefähr die Hälfte.“'),
  ('buero', '„Ich war heute super produktiv!“ – „Was hast du geschafft?“
„Meine To-do-Liste geschrieben.“'),
  ('buero', '„Ich habe zwei Stunden an einem Problem gesessen.“ – „Und?“
„Das Problem war, dass der Monitor aus war.“'),
  ('buero', 'Kollege: „Gehen wir in der Mittagspause joggen?“
„Ich mache schon Sport. Ich renne jeden Morgen dem Bus hinterher.“'),
  ('buero', 'Chef: „Sie sind schon wieder nicht an Ihrem Platz!“
„Ich arbeite gerade agil.“'),
  ('buero', 'E-Mail mit dem Betreff „WICHTIG!!!“
Inhalt: „Wer hat meinen Joghurt aus dem Kühlschrank genommen?“'),
  ('buero', 'Heute Morgen habe ich aus Versehen auf „Allen antworten“ geklickt.
Jetzt kennt mich die ganze Firma.'),
  ('buero', 'Personalchef: „Wir zahlen 1.500 Euro, nach einem halben Jahr 2.500.“
Bewerber: „Gut, dann komme ich in einem halben Jahr wieder.“'),
  ('buero', '„Sind Sie mit Ihrem Gehalt zufrieden?“
„Mit dem Gehalt schon. Nur nicht mit der Höhe.“'),
  ('buero', 'Ich wurde in der Uhrenfabrik entlassen.
Angeblich habe ich zu viele Überstunden gemacht.'),
  ('buero', 'Ich habe in der Orangensaftfabrik gekündigt.
Ich konnte mich einfach nicht konzentrieren.'),
  ('buero', 'Ich habe beim Bäcker aufgehört.
Ich wollte mein Brot anders verdienen.'),
  ('buero', 'Mein Chef will, dass ich eine Präsentation über Zeitmanagement halte.
Ich bin nur noch nicht dazu gekommen.'),
  ('buero', 'Chef: „Ab heute ist unser Büro papierlos.“
Mitarbeiter: „Super. Und wo soll ich die Anweisung jetzt ausdrucken?“'),
  ('buero', 'Kollege: „Ich bin heute im Homeoffice.“ – „Du sitzt doch direkt neben mir.“
„Körperlich ja. Geistig bin ich zu Hause.“'),
  ('buero', 'Teambuilding:
Wenn alle gemeinsam auf den Feierabend warten.'),
  ('buero', '„Was machst du als Projektmanager eigentlich den ganzen Tag?“
„Ich frage andere, wann sie fertig sind.“'),
  ('buero', '„Warum arbeitest du so gern im Team?“
„Dann kann ich die Schuld besser verteilen.“'),
  ('buero', 'Chef: „Sie haben die ganze Woche nichts gemacht!“
„Ich wollte die Kollegen nicht unter Druck setzen.“'),
  ('buero', '„Chef, darf ich morgen früher gehen? Meine Frau will mit mir Möbel kaufen.“ – „Auf keinen Fall.“
„Danke, Chef! Ich wusste, Sie lassen mich nicht im Stich.“'),
  ('buero', 'Was ist das Gegenteil von einem Meeting?
Arbeiten.'),
  ('buero', 'Stellenanzeige: „Wir sind wie eine Familie.“
Übersetzt: „Pünktlich Feierabend gibt es hier nicht.“'),
  ('buero', '„Hast du kurz fünf Minuten?“
Das gefährlichste Wort im Büro ist „kurz“.'),
  ('buero', 'Der Kopierer funktioniert immer.
Außer, man hat es eilig.'),
  ('buero', 'Chef: „Ich bin offen für jede Kritik.“ – „Dann hätte ich da etwas …“
„Aber nicht jetzt.“'),
  ('buero', 'Warum ist die Kaffeemaschine wichtiger als der Chef?
Ohne Kaffeemaschine läuft hier gar nichts.'),
  ('buero', '„Wie lang ist bei euch die Mittagspause?“
„So lange, bis der Chef es merkt.“'),
  ('buero', 'Ich habe eine Allergie gegen Montagsmeetings.
Symptome: Gähnen, Augenrollen und plötzliche Zahnarzttermine.'),
  ('buero', '„Haben Sie Hobbys?“
„Ja. Feierabend.“'),
  ('buero', 'Chef: „Warum haben Sie gestern nicht angerufen, dass Sie krank sind?“
„Ich war zu krank zum Telefonieren. Aber ich hab''s auf Instagram gepostet.“'),
  ('buero', 'Büro-Mathematik:
5 Minuten Pause + 1 Kaffee + 1 Kollege mit Neuigkeiten = 45 Minuten.'),
  ('buero', '„Was machst du eigentlich im Homeoffice?“
„Meistens die Wäsche.“'),
  ('nerd', 'Warum verwechseln Programmierer Halloween und Weihnachten?
Weil OCT 31 = DEC 25.'),
  ('nerd', 'Es gibt 10 Arten von Menschen:
Die, die Binär verstehen, und die anderen.'),
  ('nerd', 'Ein SQL-Query geht in eine Bar, sieht zwei Tische und fragt:
„Darf ich euch joinen?“'),
  ('nerd', 'Wie viele Programmierer braucht man, um eine Glühbirne zu wechseln?
Keinen. Das ist ein Hardware-Problem.'),
  ('nerd', '„Schatz, hol bitte ein Brot. Und wenn es Eier gibt, bring sechs mit.“
Der Programmierer kommt mit sechs Broten zurück: „Es gab Eier.“'),
  ('nerd', 'Warum gehen Programmierer nicht gern in die Natur?
Zu viele Bugs.'),
  ('nerd', 'Ich würde dir einen UDP-Witz erzählen.
Aber ich weiß nicht, ob er ankommt.'),
  ('nerd', '„Willst du einen TCP-Witz hören?“
„Ja, ich will einen TCP-Witz hören.“
„Okay, ich erzähle dir jetzt einen TCP-Witz.“'),
  ('nerd', 'Was trinken Programmierer am liebsten?
Java.'),
  ('nerd', 'Mein Passwort ist die letzte Ziffer von Pi.'),
  ('nerd', 'Warum war der Laptop so müde?
Er hatte zu viele Tabs offen.'),
  ('nerd', 'Ein Physiker, ein Chemiker und ein Informatiker sitzen im Auto. Plötzlich geht der Motor aus.
Der Informatiker: „Lasst uns alle aussteigen und wieder einsteigen.“'),
  ('nerd', 'Es gibt zwei schwierige Dinge in der Informatik:
Cache-Invalidierung, Namensgebung und Off-by-one-Fehler.'),
  ('nerd', 'Wie nennt man acht Hobbits?
Ein Hobbyte.'),
  ('nerd', 'Ein Informatiker stellt abends zwei Gläser ans Bett:
Eines mit Wasser, falls er Durst bekommt, und ein leeres, falls nicht.'),
  ('nerd', 'Was ist der Unterschied zwischen einem Bug und einem Feature?
Die Dokumentation.'),
  ('nerd', '„Bei mir läuft es aber!“
„Gut, dann liefern wir deinen Rechner aus.“'),
  ('nerd', 'Optimist: „Das Glas ist halb voll.“ Pessimist: „Das Glas ist halb leer.“
Informatiker: „Das Glas ist doppelt so groß wie nötig.“'),
  ('nerd', 'Um Rekursion zu verstehen, muss man zuerst Rekursion verstehen.'),
  ('nerd', 'Warum frieren Windows-Nutzer so oft?
Zu viele offene Fenster.'),
  ('nerd', 'Sagt ein Atom zum anderen: „Ich habe ein Elektron verloren.“ – „Bist du sicher?“
„Ja, ich bin positiv.“'),
  ('nerd', 'Warum sollte man Atomen nicht trauen?
Sie stecken hinter allem.'),
  ('nerd', 'Schrödingers Katze geht in eine Bar.
Und nicht.'),
  ('nerd', 'Heisenberg wird von der Polizei angehalten: „Wissen Sie, wie schnell Sie waren?“
„Nein, aber ich weiß genau, wo ich bin.“'),
  ('nerd', 'Ein Programmierer kommt nie zu spät.
Er hat nur eine hohe Latenz.'),
  ('nerd', 'Warum mögen Programmierer dunkle Bildschirme?
Weil Licht Bugs anzieht.'),
  ('nerd', 'In welcher Kneipe treffen sich Programmierer?
In der Foo-Bar.'),
  ('nerd', '„git push --force“ ist kein Befehl.
Es ist eine Drohung.'),
  ('nerd', 'Mein Code funktioniert nicht und ich weiß nicht, warum.
Mein Code funktioniert und ich weiß nicht, warum.'),
  ('nerd', '99 kleine Bugs im Code, 99 kleine Bugs.
Einen gefixt, neu kompiliert: 127 kleine Bugs im Code.'),
  ('nerd', 'Warum kam der Programmierer nicht mehr aus der Dusche?
Auf dem Shampoo stand: Auftragen, ausspülen, wiederholen.'),
  ('nerd', 'Mein WLAN heißt jetzt „Polizei-Überwachungswagen 3“.
Seitdem parken die Nachbarn woanders.'),
  ('nerd', 'Es gibt drei Arten von Menschen:
Die, die zählen können, und die, die es nicht können.'),
  ('nerd', 'Sagt i zu π: „Sei doch mal rational!“
Sagt π: „Werd du erst mal real.“'),
  ('nerd', 'Ein Neutron geht in eine Bar und fragt: „Was kostet ein Bier?“
Der Barkeeper: „Für dich? Keine Ladung.“'),
  ('nerd', 'Ich würde ja einen Chemiewitz erzählen.
Aber ich bekomme sowieso keine Reaktion.'),
  ('nerd', 'Warum ging der Computer zum Arzt?
Er hatte einen Virus.'),
  ('nerd', 'Anruf beim IT-Support: „Da steht: Drücken Sie eine beliebige Taste.“
„Ja, und?“ – „Ich finde die Taste ‚Beliebig‘ nicht.“'),
  ('nerd', '„Ihr Passwort muss mindestens 8 Zeichen lang sein.“
„Schneewittchen und die sieben Zwerge.“'),
  ('nerd', '„Wie lief dein Tag?“ – „Ich habe acht Stunden programmiert.“
„Und heute?“ – „Acht Stunden gelöscht.“'),
  ('nerd', 'Ein guter Programmierer schaut immer in beide Richtungen,
bevor er eine Einbahnstraße überquert.'),
  ('nerd', 'Meine smarte Glühbirne hat ein Update bekommen.
Jetzt geht ihr endlich ein Licht auf.'),
  ('nerd', 'Mein Kühlschrank hat jetzt WLAN.
Jetzt weiß das ganze Internet, dass ich nachts Käse esse.'),
  ('nerd', 'Warum ist der Browser so dick?
Er isst zu viele Cookies.'),
  ('nerd', 'Warum hat der Roboter Urlaub genommen?
Er musste mal richtig abschalten.'),
  ('nerd', 'Ein Ingenieur, ein Physiker und ein Mathematiker sehen in Schottland ein schwarzes Schaf. Ingenieur: „In Schottland sind die Schafe schwarz.“ Physiker: „In Schottland gibt es mindestens ein schwarzes Schaf.“
Mathematiker: „In Schottland gibt es mindestens ein Schaf, das auf mindestens einer Seite schwarz ist.“'),
  ('nerd', 'Was macht ein Mathematiker, wenn ihm kalt ist?
Er stellt sich in die Ecke. Da sind 90 Grad.'),
  ('nerd', 'Mathematiker sterben nicht.
Sie verlieren nur ihre Funktion.'),
  ('nerd', 'Was ist ein Polarbär?
Ein rechtwinkliger Bär nach dem Koordinatenwechsel.'),
  ('nerd', 'Ein Tester geht in eine Bar. Bestellt 1 Bier. 0 Bier. 99999999 Bier. −1 Bier. Eine Eidechse.
Der erste echte Gast fragt, wo die Toilette ist. Die Bar geht in Flammen auf.'),
  ('nerd', 'Wie viele Softwaretester braucht man, um eine Glühbirne zu wechseln?
Keinen. Sie melden nur, dass es dunkel ist.'),
  ('nerd', 'Warum hat sich die Tabelle von der Datenbank getrennt?
Zu viele Fremdschlüssel.'),
  ('nerd', 'Warum haben Elektriker immer gute Laune?
Sie sind gut geerdet.'),
  ('nerd', 'Was sagt der Akku zum Handy?
„Ich bin am Ende.“'),
  ('nerd', 'Mein Handy hat noch 1 % Akku.
So konzentriert habe ich noch nie gearbeitet.'),
  ('nerd', 'Ein Physiker im Café: „Einen Espresso ohne Milch, bitte.“
Kellner: „Milch ist leider aus. Darf es ein Espresso ohne Sahne sein?“'),
  ('nerd', 'Unendlich viele Mathematiker gehen in eine Bar. Der erste bestellt ein Bier, der zweite ein halbes, der dritte ein Viertel …
Der Barkeeper stellt zwei Bier hin: „Ihr müsst eure Grenzen kennen.“'),
  ('nerd', 'Drei Statistiker gehen auf die Jagd. Der erste schießt einen Meter links vorbei, der zweite einen Meter rechts.
Der dritte jubelt: „Im Durchschnitt getroffen!“'),
  ('nerd', 'Wie nennt man einen Laptop ohne Akku?
Einen Desktop.'),
  ('nerd', 'Was ist schlimmer als ein Bug?
Ein Bug, der nur freitags um 17 Uhr auftaucht.')
) as t(cat, body)
join public.categories c on c.slug = t.cat;

-- ═══════════════════════════════════════════════════════════════════
-- Erweiterung: Witz des Tages, Profile, Autoren, Duell, Reaktionen, Challenge,
-- Hinweise, Statistik und Witz-Vorrat (identisch mit erweiterung.sql)
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

-- ───────────────────────── Zum Schluss ─────────────────────────
-- Admin-Schlüssel für die Moderation (mind. 12 Zeichen, gut merken!).
-- Ersetze den Text, markiere NUR diese Zeile und führe sie aus:
--
-- select public.set_admin_key('hier-dein-geheimer-schluessel');
