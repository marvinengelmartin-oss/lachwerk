-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – 117 der beliebtesten deutschen Witze aus dem Netz
-- (klassische Volkswitze, eigene Nacherzählung; Auswahl nach Ranglisten und
-- Nutzerbewertungen bekannter Witze-Seiten). Alle sofort sichtbar.
-- Im Supabase SQL Editor einfügen und „Run“ klicken. Mehrfach ausführen ist unschädlich:
-- Witze, die es (fast) schon gibt, werden übersprungen.
-- ═══════════════════════════════════════════════════════════════════

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000',
         now() - interval '23 hours' + (t.nr - 1) * (interval '23 hours' / 117)
  from (values
    (1, 'flachwitze', 'Was ist grün, schlau und stellt viele Fragen?
Günther Lauch.'),
    (2, 'flachwitze', 'Wie nennt man einen Bumerang, der nicht zurückkommt?
Stock.'),
    (3, 'flachwitze', 'Wie heißt die Frau von Herkules?
Frau Kules.'),
    (4, 'flachwitze', 'Mir ist heute die Milch runtergefallen.
Sie war wohl nicht mehr haltbar.'),
    (5, 'flachwitze', 'Ich wollte vorhin ein Brötchen anrufen.
Aber es war belegt.'),
    (6, 'flachwitze', 'Was ist gelb und schießt?
Eine Banone.'),
    (7, 'flachwitze', '„Ich kauf mir jetzt ein Fernglas.“ – „Und dann?“
„Dann seh ich weiter.“'),
    (8, 'flachwitze', 'Was macht ein Schauspieler, der keinen Job hat?
Spielt keine Rolle.'),
    (9, 'flachwitze', 'Was ist weiß und stört beim Essen?
Eine Lawine.'),
    (10, 'flachwitze', 'Was hat jemand, der ständig im Dreieck läuft?
Kreislaufprobleme.'),
    (11, 'flachwitze', 'Was ist braun, klebrig und läuft durch die Wüste?
Ein Karamel.'),
    (12, 'flachwitze', 'Treffen sich zwei Unsichtbare.
Sagt der eine: „Lange nicht gesehen!“'),
    (13, 'flachwitze', 'Was ist rot und schlecht für die Zähne?
Ein Ziegelstein.'),
    (14, 'flachwitze', 'Wie nennt man jemanden, der nur so tut, als würde er werfen?
Scheinwerfer.'),
    (15, 'flachwitze', 'Wie nennt man einen Keks unter einem Baum?
Ein schattiges Plätzchen.'),
    (16, 'flachwitze', 'Was essen Autos am liebsten?
Parkplätzchen.'),
    (17, 'flachwitze', 'Polizist: „Ihre Papiere, bitte!“ Ich: „Schere!“
Hab ich jetzt gewonnen?'),
    (18, 'flachwitze', 'Was sagt die Null zur Acht?
„Schicker Gürtel!“'),
    (19, 'flachwitze', 'Was ist gelb und kann nicht schwimmen?
Ein Bagger.'),
    (20, 'flachwitze', '„Klopf, klopf.“ – „Wer ist da?“ – „Die Liebe deines Lebens.“
„Lüg nicht, Bier kann nicht sprechen.“'),
    (21, 'wortspiele', 'Wie heißt das Reh mit Vornamen?
Kartoffelpü.'),
    (22, 'wortspiele', 'Welche Sprache spricht man in der Sauna?
Schwitzerdeutsch.'),
    (23, 'wortspiele', 'Wohin geht ein Reh, dem die Haare ausfallen?
In die Reha.'),
    (24, 'wortspiele', 'Ich habe gestern meinen Besen verkauft.
I don''t kehr.'),
    (25, 'wortspiele', 'Wie heißt der Bruder von Elvis?
Zwölvis.'),
    (26, 'wortspiele', 'Wie nennt man ein helles Mammut?
Hellmut.'),
    (27, 'wortspiele', 'Ich wollte Spiderman anrufen.
Aber er hatte kein Netz.'),
    (28, 'wortspiele', 'Zu welchem Arzt geht Pinocchio?
Zum Holz-Nasen-Ohren-Arzt.'),
    (29, 'wortspiele', 'Was ist die Steigerung von Buchstabensuppe?
Wörtersee.'),
    (30, 'wortspiele', 'Wie heißt der Flur im Iglu?
Eisdiele.'),
    (31, 'wortspiele', 'Wie nennt man einen Ritter ohne Rüstung?
Entrüstet.'),
    (32, 'wortspiele', 'Wie nennt man einen sehr kleinen Türsteher?
Sicherheitshalber.'),
    (33, 'wortspiele', 'Was sagt der Origami-Lehrer zu seinem Schüler?
„Das kannste knicken.“'),
    (34, 'wortspiele', 'Was passiert, wenn man Cola und Bier zusammen trinkt?
Man colabiert.'),
    (35, 'wortspiele', 'Wie heißt das klügste Gemüse?
Die Schlaubergine.'),
    (36, 'wortspiele', 'Wie nennt man einen Bauern mit Studium?
Ackerdemiker.'),
    (37, 'wortspiele', 'Warum fiel der Genitiv ins Wasser?
Weil''s Dativ ist.'),
    (38, 'tiere', 'Wie kommt ein Lurch aus dem Wasser?
Nass.'),
    (39, 'tiere', 'Zwei Kühe stehen auf der Weide. Sagt die eine: „Muh!“
Sagt die andere: „Wollte ich auch gerade sagen!“'),
    (40, 'tiere', 'Zwei Schlangen. „Sag mal, sind wir eigentlich giftig?“ – „Wieso?“
„Ich hab mir gerade auf die Zunge gebissen.“'),
    (41, 'tiere', 'Wie nennt man einen Hund, der zaubern kann?
Labrakadabrador.'),
    (42, 'tiere', 'Welchen Preis bekommen besonders leise Hunde?
Den No-Bell-Preis.'),
    (43, 'tiere', 'Warum summen Bienen?
Weil sie den Text nicht kennen.'),
    (44, 'tiere', 'Die Henne schimpft mit ihren Küken: „Wenn euer Vater das sehen könnte –
der würde sich im Grill umdrehen!“'),
    (45, 'tiere', 'Zwei Eisbären laufen durch die Wüste. „Hier ist aber viel gestreut.“
„Die müssen einen harten Winter haben.“'),
    (46, 'tiere', 'Zwei Hunde treffen sich. „Ich heiße Harald vom Schlosshof.“
„Angenehm. Mich nennen sie ‚Runter vom Sofa‘.“'),
    (47, 'tiere', 'Zwei Flöhe kommen aus dem Kino, draußen regnet es.
„Laufen wir, oder nehmen wir uns einen Hund?“'),
    (48, 'tiere', 'Was erzählt der stolze Holzwurm-Vater?
„Mein Sohn arbeitet jetzt in der Bank.“'),
    (49, 'tiere', 'Zwei Frösche sitzen am Ufer, es fängt an zu regnen.
„Schnell in den Teich, sonst werden wir nass!“'),
    (50, 'tiere', 'Zwei Hühner. Das eine: „Kikeriki!“ Das andere: „Wuff!“
„Heutzutage braucht man eben Fremdsprachen.“'),
    (51, 'tiere', 'Wie nennt man ein Kaninchen im Fitnessstudio?
Pumpernickel.'),
    (52, 'tiere', 'Warum fliegen Vögel im Winter in den Süden?
Zu Fuß wäre es zu weit.'),
    (53, 'schule', 'Mutter: „Fritzchen, was hast du heute in der Schule gelernt?“
„Offenbar nicht genug. Ich muss morgen wieder hin.“'),
    (54, 'schule', 'Lehrer: „Fritzchen, du kommst schon wieder zu spät!“
„Macht nichts, Sie doch auch.“'),
    (55, 'schule', 'Lehrer: „Ich lege vier Eier auf den Tisch, du legst vier dazu. Wie viele sind es?“
„Tut mir leid, ich kann keine Eier legen.“'),
    (56, 'schule', '„Fritzchen, ein Zitronenfalter ist gelb. Deiner ist grün!“
„Der ist halt noch nicht reif.“'),
    (57, 'schule', 'Lehrer: „Was ergibt sieben mal sieben?“
„Ganz feinen Sand.“'),
    (58, 'schule', 'Fritzchen wirft sein Pausenbrot aus dem Fenster. „War das Absicht?“
„Nein, Wurst und Käse.“'),
    (59, 'schule', 'Lehrer: „Hoffentlich erwische ich dich nie wieder beim Abschreiben!“
„Das hoffe ich auch.“'),
    (60, 'schule', 'Lehrerin: „‚Ich bin schön.‘ Welche Zeitform ist das?“
„Vergangenheit.“'),
    (61, 'schule', 'Lehrer: „Das hier ist nicht der Ort zum Schlafen!“
„Geht schon, wenn Sie etwas leiser reden.“'),
    (62, 'schule', 'Lehrer: „Was ist flüssiger als Wasser?“
„Hausaufgaben. Die sind überflüssig.“'),
    (63, 'schule', 'Was ist die Steigerung von leer?
Lehrer.'),
    (64, 'schule', 'Lehrerin: „Welche Sinne kennt ihr?“
„Schwachsinn, Blödsinn und Unsinn.“'),
    (65, 'schule', 'Lehrer: „Was ist die Mehrzahl von Sandkorn?“
„Wüste.“'),
    (66, 'schule', 'Lehrerin: „Mehr als eine Fünf minus kann ich dir in Französisch nicht geben.“
„Gracias!“'),
    (67, 'schule', '„Fritzchen, wie heißt das Zauberwort mit zwei t?“
„Flott!“'),
    (68, 'schule', 'Fritzchen an den Weihnachtsmann: „Ich war das ganze Jahr brav. Na ja, meistens. Ab und zu …“
„Weißt du was, ich kauf''s mir selbst.“'),
    (69, 'buero', 'Chef: „Sie kommen diese Woche schon zum vierten Mal zu spät. Was schließen Sie daraus?“
„Dass heute Donnerstag ist.“'),
    (70, 'buero', '„Chef, am Montag komme ich etwas später.“ – „Wann denn?“
„Dienstag.“'),
    (71, 'buero', '„Wie viele Leute arbeiten eigentlich in Ihrer Firma?“
„Ungefähr die Hälfte.“'),
    (72, 'buero', '„Chef, mein Gehalt steht in keinem Verhältnis zu meiner Leistung!“
„Ich weiß. Aber verhungern lassen können wir Sie ja auch nicht.“'),
    (73, 'buero', 'Chef: „Warum kommen Sie erst jetzt?“
„Sie haben doch gesagt, ich soll die Zeitung zu Hause lesen.“'),
    (74, 'buero', '„Was sind Ihre beruflichen Ziele?“ – „Feierabend.“ – „Und langfristig?“ – „Wochenende.“
„Und auf ganz lange Sicht?“ – „Urlaub.“'),
    (75, 'buero', 'Was ist der Unterschied zwischen Gott und einem Chef?
Gott weiß, dass er kein Chef ist.'),
    (76, 'buero', 'Was trinken Chefs am liebsten?
Leitungswasser.'),
    (77, 'buero', 'Was macht ein Clown im Büro?
Faxen.'),
    (78, 'buero', 'Kunde: „Ihr Chef ist doch da, ich hab ihn durchs Fenster gesehen!“
Sekretärin: „Er Sie auch.“'),
    (79, 'buero', 'Chef: „Ich übertrage Ihnen mehr Verantwortung.“
„Ab sofort sind Sie für alles zuständig, was schiefgeht.“'),
    (80, 'buero', 'Ein Beamter zum anderen: „Was haben die Leute bloß gegen uns?“
„Wir tun doch gar nichts.“'),
    (81, 'buero', '„Chef, entweder ich bekomme eine Gehaltserhöhung …“
„… oder ich erzähle allen, dass ich eine bekommen habe.“'),
    (82, 'nerd', '„Schatz, hol bitte ein Brot. Und wenn sie Eier haben, bring sechs.“
Der Informatiker kommt mit sechs Broten nach Hause.'),
    (83, 'nerd', 'Wie viele Programmierer braucht man, um eine Glühbirne zu wechseln?
Keinen. Das ist ein Hardwareproblem.'),
    (84, 'nerd', 'Ein Spaziergänger fragt den Informatiker mit dem Kinderwagen: „Junge oder Mädchen?“
„Ja.“'),
    (85, 'nerd', 'Was macht ein Informatiker, wenn sein Auto nicht anspringt?
Aussteigen und wieder einsteigen.'),
    (86, 'nerd', '„Wie ist das Wetter bei euch?“ – „Caps Lock.“
„Shift ohne Ende.“'),
    (87, 'nerd', 'Was ist der letzte Wunsch eines Programmierers?
„Bitte ein Bit.“'),
    (88, 'nerd', 'Fehlermeldung: „Keine Tastatur gefunden.“
„Drücken Sie eine beliebige Taste, um fortzufahren.“'),
    (89, 'nerd', 'Woran erkennt man einen extrovertierten Informatiker?
Er schaut beim Reden auf DEINE Schuhe.'),
    (90, 'nerd', 'Ich habe mein Passwort auf „falsch“ geändert.
Wenn ich es vergesse, sagt mir der Rechner: „Ihr Passwort ist falsch.“'),
    (91, 'nerd', 'Was macht ein Pirat am Computer?
Er drückt die Enter-Taste.'),
    (92, 'nerd', 'Was steht auf dem Grabstein eines Mathematikers?
„Damit hat er nicht gerechnet.“'),
    (93, 'nerd', 'Warum verwechseln Informatiker Halloween und Weihnachten?
Weil OCT 31 = DEC 25.'),
    (94, 'nerd', 'Drei Leute steigen in einen leeren Bus, fünf steigen wieder aus. Sagt der Mathematiker:
„Wenn jetzt zwei einsteigen, ist er wieder leer.“'),
    (95, 'nerd', 'Wie fängt ein Mathematiker einen Löwen in der Wüste?
Er setzt sich in einen Käfig und definiert sich als außen.'),
    (96, 'nerd', 'Mathematiker: „3, 5, 7 sind Primzahlen, also alle ungeraden Zahlen.“ Physiker:
„3, 5, 7 prim, 9 Messfehler, 11 prim …“'),
    (97, 'nerd', 'Es gibt drei Sorten von Mathematikern:
Die, die zählen können, und die, die es nicht können.'),
    (98, 'nerd', 'Was sind acht Hobbits?
Ein Hobbyte.'),
    (99, 'schwarz', 'Zwei Jäger im Wald, einer bricht zusammen. Der andere ruft den Notruf: „Stellen Sie erst mal sicher, dass er tot ist.“ Ein Schuss fällt.
„Okay. Und jetzt?“'),
    (100, 'schwarz', 'Treffen sich zwei Jäger.
Beide tot.'),
    (101, 'schwarz', 'Ein Skelett kommt in die Arztpraxis.
Arzt: „Bisschen spät, was?“'),
    (102, 'schwarz', 'Mein Opa ist friedlich im Schlaf gestorben.
Nicht schreiend wie seine Beifahrer.'),
    (103, 'schwarz', 'Zu verkaufen: Fallschirm, nie geöffnet.
Nur ein paar kleine rote Flecken.'),
    (104, 'schwarz', 'Ein guter Fallschirm hält fünf bis zehn Jahre.
Ein schlechter hält bis an dein Lebensende.'),
    (105, 'schwarz', 'Heute war Schrottwichteln im Kindergarten.
Jetzt sind wir die neuen Eltern von Kevin.'),
    (106, 'schwarz', 'Warum findet der Henker nie nach Hause?
Er kennt nur die Hinrichtung.'),
    (107, 'schwarz', 'Die letzten Worte des Sportlehrers:
„Alle Speere zu mir!“'),
    (108, 'schwarz', 'Im Schwimmkurs gibt es ein Problem:
Seit Tagen ist keiner aufgetaucht.'),
    (109, 'schwarz', 'Was macht man mit einem Hund ohne Beine?
Um die Häuser ziehen.'),
    (110, 'einzeiler', 'Wissenschaftler haben herausgefunden …
… und sind wieder reingegangen.'),
    (111, 'einzeiler', '237 % aller Menschen
übertreiben maßlos.'),
    (112, 'einzeiler', 'Ich habe mir eine Tarnhose gekauft.
Seitdem finde ich sie nicht mehr.'),
    (113, 'einzeiler', 'Egal, wie gut du schläfst:
Albert schläft wie Einstein.'),
    (114, 'einzeiler', 'Ich kenne einen guten Bahn-Witz.
Aber ich weiß nicht, ob er ankommt.'),
    (115, 'einzeiler', 'Ich wollte einen Witz über Baustellen erzählen.
Aber der ist noch nicht fertig.'),
    (116, 'einzeiler', '„Ihre Fahrkarte, bitte.“
Ein Satz, der mich komplett aus der Bahn geworfen hat.'),
    (117, 'einzeiler', 'Ich habe mich von meiner Freundin, dem Clown, getrennt.
Jetzt ist Schluss mit lustig.')
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
