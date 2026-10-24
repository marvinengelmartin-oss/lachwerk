-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – 25 Chef-Sprüche fürs Büro (eigene Einzeiler im Stil eines
-- selbstverliebten Abteilungsleiters). Kategorie: Büro.
-- Im Supabase SQL Editor einfügen und „Run“ klicken. Mehrfach ausführen ist unschädlich.
--
-- Drei Sprüche erscheinen sofort, danach etwa alle 9 Stunden einer (rund 8 Tage).
-- ═══════════════════════════════════════════════════════════════════

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
         now() - interval '22 hours' + (t.nr - 1) * interval '9 hours'
  from (values
    (1, 'Mein Führungsstil ist wie eine offene Tür: Jeder darf reinkommen, keiner soll was sagen.'),
    (2, 'Teamarbeit heißt: Alle arbeiten, und einer präsentiert es dem Vorstand. Raten Sie mal, wer.'),
    (3, 'Ich habe immer ein offenes Ohr für meine Mitarbeiter – das andere brauche ich zum Telefonieren.'),
    (4, 'Kritik nehme ich gerne an – solange sie positiv ist.'),
    (5, 'Bei uns ist der Kunde König. Und ich bin der, der dem König sagt, wo''s langgeht.'),
    (6, 'Fehler sind menschlich. Deshalb mache ich keine.'),
    (7, 'Ein guter Chef delegiert Aufgaben. Ein sehr guter Chef delegiert auch die Schuld.'),
    (8, 'Feedbackgespräch heißt: Ich gebe Feedback, und Sie führen das Gespräch mit sich selbst.'),
    (9, 'Ich bin nicht nachtragend. Ich vergesse nur nie etwas.'),
    (10, 'Die Kaffeemaschine ist das einzige Gerät hier, das mehr leistet als die ganze Abteilung.'),
    (11, 'Überstunden sind keine Pflicht. Sie sind eine Chance, die man nicht ablehnt.'),
    (12, 'Wir sind hier wie eine Familie: Einer bestimmt, und die anderen meckern beim Essen.'),
    (13, 'Mein Büro hat eine Glaswand, damit die Mitarbeiter sehen, wie richtiges Arbeiten aussieht.'),
    (14, 'Homeoffice ist im Prinzip Urlaub, nur mit ausgeschalteter Kamera.'),
    (15, 'Wenn ich sage „Wir müssen reden“, meine ich: Ich rede, Sie nicken.'),
    (16, 'Ich bin ein Chef, mit dem man Pferde stehlen kann – zurückbringen müssen Sie sie aber selbst.'),
    (17, 'Ein Meeting ohne Ergebnis ist nicht verloren, es ist die Grundlage fürs nächste Meeting.'),
    (18, 'Ich lobe nicht oft. Aber wenn, dann mich.'),
    (19, 'Der Unterschied zwischen mir und der Geschäftsführung? Die Geschäftsführung ahnt noch nicht, wie gut ich bin.'),
    (20, 'Gehaltserhöhung? Sie arbeiten hier für die Ehre – und Ehre ist steuerfrei.'),
    (21, 'Ich habe nichts gegen Pausen. Ich habe nur was dagegen, wenn man sie sieht.'),
    (22, 'Mein Kalender ist so voll, ich musste ein Meeting ansetzen, um die Meetings zu planen.'),
    (23, 'Zielvereinbarung heißt: Ich vereinbare die Ziele, und Sie erreichen sie.'),
    (24, 'Am Ende des Tages zählt nur eins: dass ich am Ende des Tages gut dastehe.'),
    (25, 'Meine Tür steht immer offen. Ich bin nur nie drin.')
  ) as t(nr, body)
  join public.categories c on c.slug = 'buero'
  where not exists (
    select 1 from public.jokes j
    where j.status <> 'removed'
      and extensions.similarity(j.body_norm, public.normalize_joke(t.body)) >= 0.6
  )
  returning 1
)
select count(*) as neu_eingefuegt from neu;
