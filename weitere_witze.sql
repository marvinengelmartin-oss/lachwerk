-- ═══════════════════════════════════════════════════════════════════
-- Lachwerk – 210 weitere Witze nachladen
-- NUR nötig, wenn du supabase.sql schon früher ausgeführt hast.
-- Im Supabase SQL Editor einfügen und „Run“ klicken.
--
-- Witze, die es (fast) schon gibt, werden automatisch übersprungen.
-- Mehrfach ausführen ist also unschädlich.
-- Die neuen Witze bekommen Zeitstempel aus den letzten 3 Tagen,
-- damit sie in „Heute“, „Woche“ und im Swipe-Modus auftauchen.
-- ═══════════════════════════════════════════════════════════════════

with neu as (
  insert into public.jokes (category_id, body, author_name, author_device, created_at)
  select c.id, t.body, 'Lachwerk', '00000000-0000-0000-0000-000000000000', now() - random() * interval '3 days'
  from (values
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
  join public.categories c on c.slug = t.cat
  where not exists (
    select 1 from public.jokes j
    where j.status <> 'removed'
      and extensions.similarity(j.body_norm, public.normalize_joke(t.body)) >= 0.6
  )
  returning 1
)
select count(*) as neu_eingefuegt from neu;
