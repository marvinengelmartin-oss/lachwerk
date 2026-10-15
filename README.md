# Lachwerk

Witze-Web-App **ohne Anmeldung**: Jeder kann Witze posten, liken und im Swipe-Modus neue Witze bewerten.
Rankings für **Heute**, **Woche** und **Alltime**. Reine HTML/CSS/JS-Dateien, kein Build-Schritt.

## In 5 Minuten online (Demo-Modus)

1. Auf github.com ein neues Repository anlegen, z. B. `lachwerk` (öffentlich).
2. **Add file → Upload files** und alle Dateien aus diesem Ordner hineinziehen. Danach **Commit changes**.
3. **Settings → Pages → Build and deployment**: Source *Deploy from a branch*, Branch *main*, Ordner */ (root)*, **Save**.
4. Nach ca. 1 Minute ist die Seite erreichbar unter `https://DEIN-NAME.github.io/lachwerk/`.

Im Demo-Modus läuft alles sofort mit 150 Startwitzen. Stimmen und neue Witze bleiben aber **nur im Browser des jeweiligen Besuchers**.
Zum Ausprobieren reicht das. Für eine echte Community schaltest du den Live-Modus ein.

## Live schalten: gemeinsame Witze und Stimmen (ca. 10 Minuten)

GitHub Pages kann nur Dateien ausliefern und nichts speichern. Die Daten liegen deshalb in **Supabase** (kostenloser Plan reicht für den Start).

1. Auf [supabase.com](https://supabase.com) ein Projekt anlegen. Region: **Central EU (Frankfurt)**.
2. Im Projekt **SQL Editor → New query**, den kompletten Inhalt von `supabase.sql` einfügen und **Run** klicken.
   Das legt Tabellen, Schutzregeln und die 150 Startwitze an.
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

Nach etwa einer Minute ist die Seite live. Der gelbe Demo-Hinweis unten verschwindet.

## Moderation

Seite mit `#/admin` am Ende aufrufen, z. B. `https://DEIN-NAME.github.io/lachwerk/#/admin`, und den Admin-Schlüssel eingeben.
Dort siehst du gemeldete und ausgeblendete Witze und kannst sie **freigeben** oder **entfernen**.
Im Demo-Modus lautet der Schlüssel `demo-moderation`.

## So funktioniert es ohne Anmeldung

| Thema | Umsetzung |
|---|---|
| Wer bin ich? | Jeder Browser bekommt eine zufällige Geräte-ID (localStorage). Der Anzeigename wird beim ersten Posten abgefragt und gemerkt. |
| Ein Vote pro Person | Pro Witz und Geräte-ID genau eine Stimme. Zusätzlich max. 5 Stimmen pro Witz und Internetanschluss, max. 300 Stimmen pro Stunde und Anschluss. |
| Eigene Witze | Können nicht selbst bewertet werden. |
| Posten | Max. 10 Witze pro Gerät und 20 pro Anschluss in 24 Stunden. |
| Duplikate | Ähnlichkeitsvergleich (pg_trgm). Ab 60 % Übereinstimmung wird das Posten abgelehnt und das Original verlinkt. Schon beim Tippen erscheint ein Hinweis. |
| Ranking | Wilson-Score: fair auch bei wenigen Stimmen. Heute = 24 h, Woche = 7 Tage, Alltime = ab 20 Stimmen. |
| Swipe-Modus | Zeigt zuerst Witze mit unter 20 Stimmen, damit jeder neue Witz eine Chance bekommt. |
| Melden | Ab 3 Meldungen von verschiedenen Anschlüssen wird ein Witz ausgeblendet. Nach einer Freigabe erst ab 10. |
| Teilen | WhatsApp-Link, Link teilen und „Als Bild teilen“ (Story-Bild 1080×1920, wird im Browser erzeugt). |
| Datenschutz | Keine Cookies, keine externen Schriften, kein Tracking. IP-Adressen werden nur gesalzen gehasht gespeichert. Besucher können keine Tabelle direkt lesen, nur die freigegebenen Funktionen aufrufen. |

**Grenzen der Version ohne Anmeldung:** Wer es darauf anlegt, kann mit gelöschtem Browser-Speicher erneut abstimmen. Das IP-Limit bremst das stark, verhindert es aber nicht ganz.
Wenn die Seite wächst: Cloudflare Turnstile (unsichtbares Captcha) ergänzen oder auf die Next.js-Version mit Konten umsteigen.

## Dateien

```
index.html        Seite
app.js            App-Logik (Demo- und Live-Modus)
style.css         Gestaltung (hell und dunkel)
config.js         Supabase-Zugang (leer = Demo-Modus)
startwitze.js     150 Startwitze für den Demo-Modus
supabase.sql      Datenbank: Tabellen, Schutzregeln, Funktionen, Startwitze
impressum.html    Vorlage, bitte ausfüllen
datenschutz.html  Vorlage, bitte ausfüllen
og-image.png      Vorschaubild beim Teilen
favicon.svg       Icon
```

## Vor dem Veröffentlichen

- [ ] `impressum.html` und `datenschutz.html` ausfüllen (für eine öffentliche Seite in Deutschland Pflicht)
- [ ] In `index.html` bei `og:image` die volle Adresse eintragen, z. B. `https://DEIN-NAME.github.io/lachwerk/og-image.png`. Dann zeigt WhatsApp das Vorschaubild.
- [ ] Startwitze durchsehen. Die Liste steht unten in `supabase.sql` und in `startwitze.js`.
- [ ] Moderation testen: einen Witz melden und unter `#/admin` freigeben
- [ ] Eigene Domain (optional): Settings → Pages → Custom domain

## Lokal ausprobieren

`index.html` per Doppelklick im Browser öffnen. Der Demo-Modus funktioniert ohne Server.
