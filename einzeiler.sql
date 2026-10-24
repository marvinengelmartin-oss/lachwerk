-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – neue Kategorie „Einzeiler“ mit 30 Witzen (kurz, eine Zeile, eine Pointe)
-- Im Supabase SQL Editor einfügen und „Run“ klicken. Mehrfach ausführen ist unschädlich.
--
-- Drei Witze erscheinen sofort, danach etwa alle 10 Stunden einer (rund 12 Tage).
-- ═══════════════════════════════════════════════════════════════════

insert into public.categories (slug, name, position)
values ('einzeiler', 'Einzeiler', 8)
on conflict (slug) do nothing;

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
         now() - interval '26 hours' + (t.nr - 1) * interval '10 hours'
  from (values
    (1, 'Ich wollte heute früh ins Bett, aber dann kam das Internet dazwischen.'),
    (2, 'Ordnung ist das halbe Leben – ich wohne in der anderen Hälfte.'),
    (3, 'Früher war ich unentschlossen, heute bin ich mir da nicht mehr so sicher.'),
    (4, 'Mein Wecker und ich haben eine Abmachung: Er klingelt, ich ignoriere ihn.'),
    (5, 'Meine Pflanzen und ich brauchen dasselbe: mehr Sonne und weniger Montag.'),
    (6, 'Sport ist Mord – und ich bin kein Mörder.'),
    (7, 'Ich fange am Montag an. Welcher Montag, steht noch nicht fest.'),
    (8, 'Mein Arzt sagt, ich soll weniger Fleisch essen – jetzt schneide ich die Schnitzel dünner.'),
    (9, 'Lieber zwei Kilo zu viel als ein Stück Kuchen zu wenig.'),
    (10, 'Ich bin nicht klein, ich bin nur weit weg.'),
    (11, 'Geld allein macht nicht glücklich – man muss es auch ausgeben.'),
    (12, 'Ich bin so pleite, mein Sparschwein macht schon Intervallfasten.'),
    (13, 'Der frühe Vogel kann mich mal.'),
    (14, 'Ich esse gesund: Pommes sind schließlich Kartoffeln.'),
    (15, 'Ich habe ein fotografisches Gedächtnis – leider ohne Speicherkarte.'),
    (16, 'Ich bin ein Morgenmensch – sobald es Mittag ist.'),
    (17, 'Gestern habe ich mit dem Joggen angefangen, heute habe ich damit aufgehört.'),
    (18, 'Mein Navi und ich sind uns einig: Wir wissen beide nicht, wo wir sind.'),
    (19, 'Ich trinke Kaffee nur zu besonderen Anlässen – zum Beispiel, wenn ich wach bin.'),
    (20, 'Die Waage ist nicht mein Feind, sie ist nur sehr ehrlich und sehr unhöflich.'),
    (21, 'Wer Rechtschreibfehler findet, darf sie behalten.'),
    (22, 'Mein Fitnessstudio-Vertrag ist meine teuerste Spende.'),
    (23, 'Ich mache jeden Tag Sport: Ich renne meinen Pflichten hinterher.'),
    (24, 'Ich hab mich gestern im Spiegel gesehen und dachte: Der Typ braucht Urlaub.'),
    (25, 'Mein Kühlschrank und ich haben eins gemeinsam: Beide werden nachts geplündert.'),
    (26, 'Ich bin nicht unpünktlich, ich mache nur spannende Auftritte.'),
    (27, 'Ich habe meinem Chef gesagt, ich brauche mehr Herausforderungen – jetzt muss ich pünktlich kommen.'),
    (28, 'Ich bin Multitasking-fähig: Ich kann gleichzeitig nichts tun und trotzdem müde sein.'),
    (29, 'Diät-Tipp: Nur essen, wenn die Waage gerade nicht hinschaut.'),
    (30, 'Mein Plan für heute: Erst nichts tun, danach eine Pause machen.')
  ) as t(nr, body)
  join public.categories c on c.slug = 'einzeiler'
  where not exists (
    select 1 from public.jokes j
    where j.status <> 'removed'
      and extensions.similarity(j.body_norm, public.normalize_joke(t.body)) >= 0.6
  )
  returning 1
)
select count(*) as neu_eingefuegt from neu;
