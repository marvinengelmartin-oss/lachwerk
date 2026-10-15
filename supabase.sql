-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – Datenbank für die Version OHNE Anmeldung
-- Einmal komplett im Supabase SQL Editor ausführen (Run).
-- Danach unten den Admin-Schlüssel setzen (letzte Zeile).
-- ═══════════════════════════════════════════════════════════════════
--
-- Prinzip: Jeder Browser bekommt eine zufällige Geräte-ID (localStorage).
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
  select j.id, j.body, c.slug as category_slug, j.author_name, j.author_device, j.created_at,
         j.up_count, j.down_count, j.report_count, j.status, j.reviewed_at,
         public.wilson_lower(j.up_count, j.down_count) as score
  from public.jokes j
  join public.categories c on c.id = j.category_id;

-- ───────────────────────── Lesen ─────────────────────────

-- Ranking: day = letzte 24 h, week = letzte 7 Tage, all = ab 20 Stimmen
create function public.get_ranking(p_device uuid, p_range text, p_category text default null,
                                   p_limit int default 30, p_offset int default 0)
returns table (id bigint, body text, category_slug text, author_name text, created_at timestamptz,
               up_count int, down_count int, score double precision, is_own boolean, my_vote smallint)
language sql stable security definer set search_path = public as $$
  select f.id, f.body, f.category_slug, f.author_name, f.created_at, f.up_count, f.down_count, f.score,
         f.author_device = p_device, v.value
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
         f.author_device = p_device, v.value
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
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  if p_value is null or p_value not in (-1, 0, 1) then raise exception 'invalid_value'; end if;

  select j.author_device into v_author from public.jokes j where j.id = p_joke and j.status = 'visible';
  if not found then raise exception 'joke_not_found'; end if;
  if v_author = p_device then raise exception 'own_joke'; end if;

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

-- Witz posten. Gibt die neue ID zurück.
create function public.post_joke(p_device uuid, p_name text, p_category text, p_body text)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  h      text := public.client_ip_hash();
  v_name text := trim(coalesce(p_name, ''));
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_cat  int;
  v_dup  bigint;
  v_id   bigint;
begin
  if p_device is null then raise exception 'invalid_device'; end if;
  if char_length(v_name) not between 2 and 24 then raise exception 'invalid_name'; end if;
  if char_length(v_body) not between 10 and 500 then raise exception 'invalid_body'; end if;

  select c.id into v_cat from public.categories c where c.slug = p_category;
  if v_cat is null then raise exception 'invalid_category'; end if;

  -- max. 10 Witze pro Gerät und 20 pro IP in 24 Stunden
  if (select count(*) from public.jokes j where j.author_device = p_device and j.created_at > now() - interval '24 hours') >= 10
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

  insert into public.jokes (category_id, body, author_name, author_device, ip_hash)
  values (v_cat, v_body, v_name, p_device, h)
  returning jokes.id into v_id;
  return v_id;
end $$;

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
  public.post_joke(uuid, text, text, text),
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
  ('nerd',       'Nerd',       6);

-- 150 Startwitze von der „Lachwerk“-Redaktion, verteilt über die letzten 6 Tage.
-- Bewusst ohne erfundene Stimmen: Die ersten Besucher bewerten sie im Swipe-Modus.
insert into public.jokes (category_id, body, author_name, author_device, created_at)
select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000', now() - random() * interval '6 days'
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
Er hat nur eine hohe Latenz.')
) as t(cat, body)
join public.categories c on c.slug = t.cat;

-- ───────────────────────── Zum Schluss ─────────────────────────
-- Admin-Schlüssel für die Moderation (mind. 12 Zeichen, gut merken!).
-- Ersetze den Text, markiere NUR diese Zeile und führe sie aus:
--
-- select public.set_admin_key('hier-dein-geheimer-schluessel');
