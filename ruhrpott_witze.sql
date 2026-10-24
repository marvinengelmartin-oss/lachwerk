-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – 25 Witze im Ruhrpott-Stil (eigene Witze der Lachwerk-Redaktion)
-- Im Supabase SQL Editor einfügen und „Run“ klicken.
--
-- Die Witze erscheinen nach und nach: zwei schon heute, danach etwa alle
-- 11 Stunden einer, verteilt über rund 10 Tage. So bekommt „Heute“ Nachschub.
-- Witze, die es (fast) schon gibt, werden übersprungen. Mehrfach ausführen ist unschädlich.
-- ═══════════════════════════════════════════════════════════════════

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
         now() - interval '20 hours' + (t.nr - 1) * interval '11 hours'
  from (values
    (1, 'flachwitze', 'Hömma, mein Navi sacht: „Bitte wenden.“
Hab ich gemacht. Jetzt liegt mein Auto auf''m Dach.'),
    (2, 'flachwitze', 'Ich hab ''n Gedächtnis wie ''n Elefant.
Ich weiß nur nich mehr, wo ich den hingestellt hab.'),
    (3, 'flachwitze', 'Ich hab ''nen Kaktus geschenkt gekricht. Nach drei Wochen war der tot.
Ich glaub, ich hab den zu oft gedrückt.'),
    (4, 'flachwitze', 'Ich bin um sechs aufgestanden, hab gefrühstückt, Sport gemacht, geduscht.
Dann hat der Wecker geklingelt.'),
    (5, 'flachwitze', 'Ich beim Schuster: „Können Se meine Schuhe neu besohlen?“ – „Klar, wann brauchen Se die?“
„Ich hab se an.“'),
    (6, 'flachwitze', 'Ich im Baumarkt: „Ham Se Schrauben?“ – „Wie lang?“
„Ich wollt die kaufen, nich mieten.“'),
    (7, 'flachwitze', 'Ich beim Bäcker: „Ham Se Brötchen von gestern?“ – „Ja.“
„Dann backen Se doch einfach weniger!“'),
    (8, 'flachwitze', 'Mein Fitnessstudio hat angerufen: „Wir vermissen Sie!“
Ich so: „Dann kommt doch vorbei.“'),
    (9, 'flachwitze', 'Kumpel fragt: „Wie war dein Urlaub?“ – „Super, zehn Tage Sonne.“ – „Wo warst du denn?“
„Im Solarium.“'),
    (10, 'flachwitze', 'Mein Arzt sacht: „Sie müssen mal richtig abschalten.“
Hab ich gemacht. Jetzt is der Fernseher aus und ich weiß nich, wat ich machen soll.'),
    (11, 'tiere', 'Ich hab meinem Hund beigebracht, die Zeitung zu holen.
Jetzt hab ich drei Abos, die ich nie bestellt hab.'),
    (12, 'tiere', 'Treffen sich zwei Möwen am Baldeneysee. Sacht die eine: „Komm, wir fliegen nach Mallorca.“
Sacht die andere: „Wat soll ich da? Hier gibt''s doch auch Pommes.“'),
    (13, 'tiere', 'Mein Kumpel hat ''nen Wellensittich, der kann „Hömma“ sagen.
Mehr nich. Reicht aber im Ruhrpott.'),
    (14, 'tiere', 'Stehen zwei Kühe auf der Weide bei Bottrop. Sacht die eine: „Muuuh!“
Sacht die andere: „Hömma, nich so laut. Hier wohnen Leute.“'),
    (15, 'buero', 'Sacht der Chef: „Sie sind ja schon wieder zu spät!“
Ich so: „Nee, ich bin nur früh dran für morgen.“'),
    (16, 'buero', 'Chef sacht: „Wir müssen mehr miteinander reden.“
Seitdem ruft der mich jeden Tag an. Ich sitz direkt neben ihm.'),
    (17, 'buero', 'Vorstellungsgespräch. „Wat ist Ihre größte Stärke?“ – „Ich kann gut zuhören.“ – „Und Ihre Schwäche?“
„Wie bitte?“'),
    (18, 'schule', 'Lehrer: „Wat ist die Hauptstadt vom Ruhrgebiet?“
Fritzchen: „Kommt drauf an, wen Se fragen.“'),
    (19, 'schule', 'Lehrerin: „Nenn mir ''n Lebewesen, dat unter Tage arbeitet.“
Fritzchen: „Mein Opa. Aber nur bis Schicht.“'),
    (20, 'wortspiele', 'Sacht die Kassiererin: „Sammeln Sie Punkte?“
Ich so: „Nee. Nur Kilos.“'),
    (21, 'wortspiele', '„Papa, wat is ''n Optimist?“
„Einer, der im Ruhrpott Sonnencreme einpackt.“'),
    (22, 'nerd', 'Omma: „Junge, wie mach ich hier ''n Foto?“ – „Auf den Kreis drücken.“
Jetzt hat se vierzig Fotos von ihrem Daumen. Und ''n Video, wo se fragt: „Jetzt?“'),
    (23, 'nerd', 'Ich hab mir ''ne Smartwatch gekauft. Die sacht jeden Abend: „Sie haben Ihr Tagesziel erreicht!“
Ich hatte mir aber gar nix vorgenommen.'),
    (24, 'nerd', 'Mein Kumpel Kalle fährt jetzt E-Auto.
Hat er sich aber nur gekauft, weil man beim Laden so schön in Ruhe Pommes essen kann.'),
    (25, 'nerd', 'Ich hab meine PIN vergessen. Jetzt steh ich am Automaten und rate.
Hinter mir ''ne Schlange, die miträt.')
  ) as t(nr, cat, body)
  join public.categories c on c.slug = t.cat
  where not exists (
    select 1 from public.jokes j
    where j.status <> 'removed'
      and extensions.similarity(j.body_norm, public.normalize_joke(t.body)) >= 0.6
  )
  returning 1
)
select count(*) as neu_eingefuegt from neu;
