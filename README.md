# Lachwerk

Witze-Web-App: Lesen, Liken und Bewerten im Swipe-Modus geht **ohne Konto**. Zum **Posten** registriert man sich mit E-Mail und Passwort.
Rankings für **Heute**, **Woche** und **Alltime**. Reine HTML/CSS/JS-Dateien, kein Build-Schritt.

## In 5 Minuten online (Demo-Modus)

1. Auf github.com ein neues Repository anlegen, z. B. `lachwerk` (öffentlich).
2. **Add file → Upload files** und alle Dateien aus diesem Ordner hineinziehen. Danach **Commit changes**.
3. **Settings → Pages → Build and deployment**: Source *Deploy from a branch*, Branch *main*, Ordner */ (root)*, **Save**.
4. Nach ca. 1 Minute ist die Seite erreichbar unter `https://lachwerk.github.io/`.

Im Demo-Modus läuft alles sofort mit 360 Startwitzen. Jeden Tag erscheint unter „Heute“ automatisch eine neue Auswahl. Stimmen und neue Witze bleiben aber **nur im Browser des jeweiligen Besuchers**.
Zum Ausprobieren reicht das. Für eine echte Community schaltest du den Live-Modus ein.

## Live schalten: gemeinsame Witze und Stimmen (ca. 10 Minuten)

GitHub Pages kann nur Dateien ausliefern und nichts speichern. Die Daten liegen deshalb in **Supabase** (kostenloser Plan reicht für den Start).

1. Auf [supabase.com](https://supabase.com) ein Projekt anlegen. Region: **Central EU (Frankfurt)**.
2. Im Projekt **SQL Editor → New query**, den kompletten Inhalt von `supabase.sql` einfügen und **Run** klicken.
   Das legt Tabellen, Schutzregeln und die 360 Startwitze an. Sie sind über 35 Tage vorgeplant:
   Jeden Tag erscheinen etwa 10 neue, damit „Heute“ auch ohne Beiträge von Besuchern gefüllt ist.
3. Admin-Schlüssel für die Moderation setzen (mindestens 12 Zeichen, gut merken):
   ```sql
   select public.set_admin_key('hier-dein-geheimer-schluessel');
   ```
4. Unter **Project Settings → API** (bzw. **API Keys**) die **Project URL** und den **anon / publishable** Key kopieren.
5. In GitHub die Datei `config.js` öffnen, auf den Stift klicken, beide Werte eintragen, **Commit changes**:
   ```js
   window.LACHWERK_CONFIG = {
     supabaseUrl: "https://abcdefgh.supabase.co",
     supabaseAnonKey: "eyJhbGciOi...",
   };
   ```
   Der anon-Key ist öffentlich und darf dort stehen. Den **service_role / secret** Key niemals eintragen.

6. Unter **Authentication → URL Configuration**:
   - **Site URL:** `https://lachwerk.github.io/`
   - **Redirect URLs:** dieselbe Adresse hinzufügen
   Dorthin führen die Links in den Bestätigungs- und Passwort-E-Mails.
7. Optional: Unter **Authentication → Emails** die Texte der E-Mails auf Deutsch anpassen.
   Der eingebaute E-Mail-Versand von Supabase schafft nur wenige E-Mails pro Stunde. Für mehr Nutzer unter **Authentication → SMTP** einen eigenen Versand eintragen (z. B. Brevo, kostenlos bis 300/Tag).

Nach etwa einer Minute ist die Seite live. Der gelbe Demo-Hinweis unten verschwindet.

## Weitere Witze nachladen

Du hast `supabase.sql` schon früher ausgeführt? Dann führe im SQL Editor `weitere_witze.sql` aus.
Es kommen bis zu 210 neue Witze dazu. Witze, die es schon gibt, werden übersprungen. Mehrfach ausführen ist unschädlich.
Bei einer Neueinrichtung brauchst du die Datei nicht, `supabase.sql` enthält bereits alle 360.

### Zusätzliche Witz-Pakete

- `ruhrpott_witze.sql`: 25 Witze im Ruhrpott-Stil, erscheinen nach und nach über rund 10 Tage
- `schwarzer_humor.sql`: Kategorie „Schwarzer Humor“ mit 17 Witzen, erscheinen über rund 9 Tage
- `einzeiler.sql`: Kategorie „Einzeiler“ mit 30 kurzen Witzen, erscheinen über rund 12 Tage
- `chef_sprueche.sql`: 25 Chef-Sprüche in der Kategorie „Büro“, erscheinen über rund 8 Tage

Jeweils im SQL Editor ausführen. Vorhandene Witze werden übersprungen.

## Funktionen der Erweiterung

Für eine schon eingerichtete Datenbank einmal `erweiterung.sql` im SQL Editor ausführen (bei Neueinrichtung steckt sie in `supabase.sql`).

| Funktion | So funktioniert es |
|---|---|
| Witz des Tages | Jeden Abend um 20 Uhr (deutsche Zeit) wird der beste Witz der letzten 24 Stunden gekrönt. Ohne Zeitplan: Die Krönung passiert beim nächsten Seitenaufruf danach. Zu sehen unter `#/highlights`, das Story-Bild trägt dann die Krone. |
| Reaktionen | 😂 🙄 💀 unter jedem Witz, eine pro Gerät. Daraus: „Lacher“, „Größter Seufzer“ und „Schwärzester“ der Woche. |
| Duell | `#/duell`: zwei Witze, einer gewinnt. Eigene Elo-Wertung, beeinflusst das normale Ranking nicht. Duell-Champions ab 5 Duellen. |
| Autoren | `#/autoren`: Witzbold der Woche und Alltime (Wilson-Score über alle Stimmen eines Autors, mind. 5 bzw. 20 Stimmen). |
| Profile | `#/u/NAME`: Witze, Likes, Lacher-Quote und Abzeichen. Erreichbar über den Namen unter jedem Witz. |
| Hinweise | Angemeldete Autoren sehen oben in der Bestenliste, wenn ihr Witz in den Top 3 ist, gekrönt wurde oder 10/25/50/100 … Likes geknackt hat. |
| Serie | Wer an mehreren Tagen in Folge bewertet, sammelt eine Serie (🔥) mit Abzeichen nach 3, 7 und 30 Tagen. Nur im Browser gespeichert. |
| Challenge | Wochenthema mit eigener Rangliste unter `#/challenge`. Beim Posten ankreuzen. Neue Challenges legst du unter `#/admin` → Challenge an. |
| Statistik | `#/admin` → Statistik: Besucher (abstimmende Geräte), Stimmen, Reaktionen, Duelle, neue Witze und Konten pro Tag. |
| Vorrat | `#/admin` → Vorrat: Witze einfügen (Leerzeile trennt Witze), Anzahl pro Tag wählen, fertig. Sie erscheinen nach und nach. |
| App | Installierbar (PWA): Symbol auf dem Startbildschirm, Kurzbefehle, funktioniert auch bei Funkloch. |
| Google | `witze/` enthält statische Seiten je Kategorie, dazu `sitemap.xml` und `robots.txt`. Bei Google Search Console die Sitemap einreichen. |

## Moderation

Seite mit `#/admin` am Ende aufrufen, z. B. `https://lachwerk.github.io/#/admin`, und den Admin-Schlüssel eingeben.
Dort siehst du gemeldete und ausgeblendete Witze und kannst sie **freigeben** oder **entfernen**.
Im Demo-Modus lautet der Schlüssel `demo-moderation`. Konten gelten dort nur im jeweiligen Browser und haben kein echtes Passwort.

## So funktioniert es ohne Anmeldung

| Thema | Umsetzung |
|---|---|
| Konto | Nur zum Posten nötig. Registrierung mit Benutzername, E-Mail und Passwort über Supabase Auth, mit E-Mail-Bestätigung und „Passwort vergessen“. Der Benutzername erscheint unter den Witzen. |
| Gäste | Jeder Browser bekommt eine zufällige Geräte-ID (localStorage). Damit funktionieren Liken, Bewerten und Melden ohne Konto. |
| Ein Vote pro Person | Pro Witz und Geräte-ID genau eine Stimme. Zusätzlich max. 5 Stimmen pro Witz und Internetanschluss, max. 300 Stimmen pro Stunde und Anschluss. |
| Eigene Witze | Können nicht selbst bewertet werden, auch nicht von einem anderen Gerät aus. |
| Posten | Nur mit Konto. Max. 10 Witze pro Konto und 20 pro Anschluss in 24 Stunden. |
| Duplikate | Ähnlichkeitsvergleich (pg_trgm). Ab 60 % Übereinstimmung wird das Posten abgelehnt und das Original verlinkt. Schon beim Tippen erscheint ein Hinweis. |
| Ranking | Wilson-Score: fair auch bei wenigen Stimmen. Heute = 24 h, Woche = 7 Tage, Alltime = ab 20 Stimmen. Ist ein Zeitraum leer, zeigt die Seite automatisch die Besten der Woche bzw. aller Zeiten. |
| Swipe-Modus | Zeigt zuerst Witze mit unter 20 Stimmen, damit jeder neue Witz eine Chance bekommt. |
| Melden | Ab 3 Meldungen von verschiedenen Anschlüssen wird ein Witz ausgeblendet. Nach einer Freigabe erst ab 10. |
| Teilen | WhatsApp-Link, Link teilen und „Als Bild teilen“ (Story-Bild 1080×1920, wird im Browser erzeugt). |
| Datenschutz | Keine Cookies, keine externen Schriften, kein Tracking. IP-Adressen werden nur gesalzen gehasht gespeichert. Besucher können keine Tabelle direkt lesen, nur die freigegebenen Funktionen aufrufen. |

**Grenzen bei Gast-Stimmen:** Wer es darauf anlegt, kann mit gelöschtem Browser-Speicher erneut abstimmen. Das IP-Limit bremst das stark, verhindert es aber nicht ganz.
Wenn die Seite wächst: Cloudflare Turnstile (unsichtbares Captcha) ergänzen oder auch das Liken an ein Konto binden.

## Dateien

```
index.html        Seite
app.js            App-Logik (Demo- und Live-Modus)
style.css         Gestaltung
config.js         Supabase-Zugang (leer = Demo-Modus)
startwitze.js     360 Startwitze für den Demo-Modus
supabase.sql      Datenbank: Tabellen, Schutzregeln, Funktionen, Startwitze
weitere_witze.sql 210 neue Witze für eine schon eingerichtete Datenbank
erweiterung.sql   Witz des Tages, Duell, Reaktionen, Profile, Challenge, Statistik, Vorrat
manifest.webmanifest, sw.js, icons/   installierbare App
witze/            statische Kategorie-Seiten für Google
sitemap.xml, robots.txt
impressum.html    Vorlage, bitte ausfüllen
datenschutz.html  Vorlage, bitte ausfüllen
og-image.png      Vorschaubild beim Teilen
favicon.svg       Icon
```

## Vor dem Veröffentlichen

- [ ] `impressum.html` und `datenschutz.html` ausfüllen (für eine öffentliche Seite in Deutschland Pflicht)
- [ ] In `index.html` bei `og:image` die volle Adresse eintragen, z. B. `https://lachwerk.github.io/og-image.png`. Dann zeigt WhatsApp das Vorschaubild.
- [ ] Startwitze durchsehen. Die Liste steht unten in `supabase.sql` und in `startwitze.js`.
- [ ] Moderation testen: einen Witz melden und unter `#/admin` freigeben
- [ ] Eigene Domain (optional): Settings → Pages → Custom domain

## Lokal ausprobieren

`index.html` per Doppelklick im Browser öffnen. Der Demo-Modus funktioniert ohne Server.
