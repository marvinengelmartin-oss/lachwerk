-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – neue Kategorie „Schwarzer Humor“ mit 17 Witzen
-- (eigene bzw. klassische Witze, ohne Suizid, echte Unglücke oder Gruppen)
-- Im Supabase SQL Editor einfügen und „Run“ klicken. Mehrfach ausführen ist unschädlich.
--
-- Drei Witze erscheinen sofort, danach etwa alle 14 Stunden einer (rund 9 Tage).
-- ═══════════════════════════════════════════════════════════════════

insert into public.categories (slug, name, position)
values ('schwarz', 'Schwarzer Humor', 7)
on conflict (slug) do nothing;

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
         now() - interval '30 hours' + (t.nr - 1) * interval '14 hours'
  from (values
    (1, '„Herr Doktor, wie viel Zeit bleibt mir noch?“ – „Zehn.“ – „Zehn was? Jahre? Monate?“
„Neun, acht, sieben …“'),
    (2, 'Opa wollte, dass seine Asche an seinem Lieblingsort verstreut wird.
Jetzt liegt er im Baumarkt. Gang 7, Schrauben.'),
    (3, 'Was ist der Unterschied zwischen einem Bestatter und einem Optimisten?
Der Bestatter weiß, dass am Ende alle zu ihm kommen.'),
    (4, 'Warum haben Friedhöfe Zäune?
Weil alle unbedingt rein wollen.'),
    (5, 'Testamentseröffnung: „… und meinem Neffen Klaus, der immer in meinem Testament erwähnt werden wollte:
Hallo, Klaus!“'),
    (6, 'Arzt: „Ich habe eine gute und eine schlechte Nachricht. Die gute: Sie haben noch 24 Stunden.“ – „Und die schlechte?“
„Ich hätte Sie gestern anrufen sollen.“'),
    (7, 'Es klingelt. Vor der Tür steht der Sensenmann. Ich: „Ich hab nix bestellt.“
Er: „Ich bin auch nicht der Paketbote.“'),
    (8, 'Mein Hausarzt sagt, ich soll mich mehr bewegen.
Mein Bestatter sieht das entspannter.'),
    (9, 'Ein Skelett kommt in die Arztpraxis.
Sagt die Sprechstundenhilfe: „Sie kommen aber spät.“'),
    (10, 'Ein Mann hört auf dem Friedhof aus einem Grab Musik, die rückwärts läuft.
Der Friedhofsgärtner: „Ach, das ist Beethoven. Der dekomponiert gerade.“'),
    (11, 'Mein Arzt hat mir noch sechs Monate gegeben. Ich konnte die Rechnung nicht bezahlen.
Da hat er mir noch mal sechs Monate gegeben.'),
    (12, 'Der Verurteilte wünscht sich als Henkersmahlzeit Erdbeeren. „Die gibt es doch erst im Juni!“
„Ich kann warten.“'),
    (13, 'Warum machen Bestatter sich nie Sorgen um ihren Job?
Ihre Kundschaft stirbt nie aus.'),
    (14, 'Was steht auf dem Grabstein eines Hypochonders?
„Ich hab''s euch ja gesagt.“'),
    (15, 'Der Pfarrer bei der Beerdigung: „Möchte jemand noch etwas Gutes über den Verstorbenen sagen?“ Lange Stille.
Dann ruft einer von hinten: „Sein Bruder war schlimmer!“'),
    (16, '„Herr Doktor, ich habe solche Angst vor dem Sterben.“
„Keine Sorge, das machen Sie nur einmal.“'),
    (17, 'Mein Lieblingsort zum Entspannen ist der Friedhof.
So ruhig da. Und keiner will was von mir.')
  ) as t(nr, body)
  join public.categories c on c.slug = 'schwarz'
  where not exists (
    select 1 from public.jokes j
    where j.status <> 'removed'
      and extensions.similarity(j.body_norm, public.normalize_joke(t.body)) >= 0.6
  )
  returning 1
)
select count(*) as neu_eingefuegt from neu;
