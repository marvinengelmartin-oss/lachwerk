/* Lachwerk – App ohne Anmeldung.
 * Live-Modus: spricht direkt mit den Supabase-Funktionen aus supabase.sql.
 * Demo-Modus: gleiche Oberfläche, Daten nur im Browser (localStorage).
 */
(function () {
  "use strict";

  const CFG = window.LACHWERK_CONFIG || {};
  const LIVE = Boolean(CFG.supabaseUrl && CFG.supabaseAnonKey);
  const CATS = { flachwitze: "Flachwitze", wortspiele: "Wortspiele", tiere: "Tiere", schule: "Schule", buero: "Büro", nerd: "Nerd", schwarz: "Schwarzer Humor", einzeiler: "Einzeiler" };
  const RANGES = {
    day: { label: "Beste Witze der letzten 24 Stunden", best: "Tages&shy;bester" },
    week: { label: "Beste Witze der letzten 7 Tage", best: "Wochen&shy;bester" },
    all: { label: "Beste Witze aller Zeiten (ab 20 Stimmen)", best: "Rekord" },
  };
  const PAGE = 30;
  const DUP_THRESHOLD = 0.6;
  const DEMO_ADMIN_KEY = "demo-moderation";

  /* ───────── Speicher & Geräte-ID ───────── */
  const memory = {};
  const store = {
    get(k, d) { try { const v = localStorage.getItem("lw_" + k); return v ? JSON.parse(v) : d; } catch (e) { return k in memory ? memory[k] : d; } },
    set(k, v) { try { localStorage.setItem("lw_" + k, JSON.stringify(v)); } catch (e) { memory[k] = v; } },
  };
  const session = {
    get(k) { try { return sessionStorage.getItem("lw_" + k); } catch (e) { return memory["s_" + k] || null; } },
    set(k, v) { try { v == null ? sessionStorage.removeItem("lw_" + k) : sessionStorage.setItem("lw_" + k, v); } catch (e) { memory["s_" + k] = v; } },
  };
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => { const r = (Math.random() * 16) | 0; return (c === "x" ? r : (r & 3) | 8).toString(16); });
  }
  let DEVICE = store.get("device", null);
  if (!DEVICE) { DEVICE = uuid(); store.set("device", DEVICE); }

  /* ───────── Hilfen ───────── */
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const fmt = (n) => Number(n).toLocaleString("de-DE");
  function ago(iso) {
    const h = (Date.now() - new Date(iso).getTime()) / 36e5;
    if (h < 1) return "gerade eben";
    if (h < 24) return `vor ${Math.round(h)} Std.`;
    const d = Math.round(h / 24);
    return d === 1 ? "vor 1 Tag" : `vor ${d} Tagen`;
  }
  function wilson(up, down) {
    const n = up + down; if (n <= 0) return 0;
    const z = 1.96, p = up / n;
    return (p + (z * z) / (2 * n) - z * Math.sqrt((p * (1 - p) + (z * z) / (4 * n)) / n)) / (1 + (z * z) / n);
  }
  function norm(t) { return t.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim(); }
  function trigrams(t) {
    const s = new Set();
    for (const w of norm(t).split(" ")) { if (!w) continue; const p = "  " + w + " "; for (let i = 0; i < p.length - 2; i++) s.add(p.slice(i, i + 3)); }
    return s;
  }
  function similarity(a, b) {
    const A = trigrams(a), B = trigrams(b); if (!A.size || !B.size) return 0;
    let i = 0; for (const x of A) if (B.has(x)) i++;
    return i / (A.size + B.size - i);
  }
  const ERRORS = {
    own_joke: "Eigene Witze kannst du nicht bewerten.",
    rate_limited: "Zu viele Stimmen in kurzer Zeit. Mach kurz Pause.",
    ip_limit: "Von deinem Anschluss wurde dieser Witz schon oft bewertet.",
    joke_not_found: "Diesen Witz gibt es nicht mehr.",
    post_limit: "Du hast heute schon 10 Witze gepostet. Morgen geht es weiter.",
    invalid_name: "Dein Name braucht 2 bis 24 Zeichen.",
    not_logged_in: "Bitte melde dich an, um Witze zu posten.",
    invalid_username: "Der Benutzername braucht 3 bis 20 Zeichen: Buchstaben, Zahlen, Punkt oder Unterstrich.",
    username_taken: "Dieser Benutzername ist schon vergeben.",
    invalid_email: "Bitte gib eine gültige E-Mail-Adresse ein.",
    password_short: "Das Passwort braucht mindestens 8 Zeichen.",
    weak_password: "Das Passwort ist zu schwach. Nimm mindestens 8 Zeichen.",
    email_exists: "Mit dieser E-Mail gibt es schon ein Konto. Melde dich an.",
    invalid_credentials: "E-Mail oder Passwort stimmt nicht.",
    email_not_confirmed: "Bitte bestätige zuerst deine E-Mail-Adresse über den Link in deinem Postfach.",
    consent_missing: "Bitte bestätige, dass du die Datenschutzerklärung gelesen hast.",
    email_rate_limit: "Gerade wurden zu viele E-Mails verschickt. Versuch es in einer Stunde noch einmal.",
    password_mismatch: "Die beiden Passwörter stimmen nicht überein.",
    invalid_body: "Ein Witz braucht 10 bis 500 Zeichen.",
    invalid_category: "Wähle eine Kategorie.",
    not_admin: "Der Schlüssel stimmt nicht.",
    invalid_value: "Ungültige Eingabe.",
    demo_only: "Im Demo-Modus nicht verfügbar.",
    network: "Keine Verbindung. Prüfe dein Internet und versuch es noch einmal.",
  };
  const errorText = (e) => ERRORS[e && e.code] || "Das hat nicht geklappt. Versuch es noch einmal.";

  /* ───────── Konto (Supabase Auth, ohne Fremdbibliothek) ───────── */
  const SITE_URL = location.href.split("#")[0].split("?")[0];
  const USERNAME_RE = /^[A-Za-z0-9_.äöüÄÖÜß]{3,20}$/;
  let AUTH = store.get("auth", null); // { access_token, refresh_token, expires_at, email, username } bzw. { demo: true, … }
  if (AUTH && LIVE === Boolean(AUTH.demo)) AUTH = null;     // Demo-Konto nicht im Live-Modus verwenden und umgekehrt
  function setAuth(a) { AUTH = a; store.set("auth", a); if (typeof renderNav === "function") renderNav(route().view); }
  const authError = (code) => { const e = new Error(code); e.code = code; return e; };
  function mapAuthError(data, status) {
    const c = data.error_code || data.code || data.error || "";
    const m = String(data.msg || data.error_description || data.message || "").toLowerCase();
    if (c === "email_not_confirmed" || m.includes("not confirmed")) return "email_not_confirmed";
    if (c === "invalid_credentials" || c === "invalid_grant" || m.includes("invalid login")) return "invalid_credentials";
    if (c === "weak_password" || m.includes("password should")) return "weak_password";
    if (c === "user_already_exists" || c === "email_exists" || m.includes("already registered")) return "email_exists";
    if (c === "email_address_invalid" || c === "validation_failed" || m.includes("invalid format")) return "invalid_email";
    if (String(c).includes("rate_limit") || status === 429) return "email_rate_limit";
    return "auth_failed";
  }
  async function authReq(path, { method = "POST", body, token } = {}) {
    const headers = { "Content-Type": "application/json", apikey: CFG.supabaseAnonKey };
    if (token) headers.Authorization = "Bearer " + token;
    let res;
    try { res = await fetch(CFG.supabaseUrl.replace(/\/$/, "") + "/auth/v1/" + path, { method, headers, body: body ? JSON.stringify(body) : undefined }); }
    catch (e) { throw authError("network"); }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) { const e = authError(mapAuthError(data, res.status)); e.status = res.status; throw e; }
    return data;
  }
  async function startSession(data) {
    const a = {
      access_token: data.access_token, refresh_token: data.refresh_token,
      expires_at: Number(data.expires_at) || Math.floor(Date.now() / 1000) + Number(data.expires_in || 3600),
      email: (data.user && data.user.email) || "", username: "",
    };
    AUTH = a; // vorläufig, damit my_profile mit Token läuft
    try { const r = (await rpc("my_profile", {}))[0]; a.username = (typeof r === "string" ? r : r && r.username) || ""; } catch (e) { /* Name folgt beim nächsten Laden */ }
    setAuth(a);
  }
  let refreshing = null;
  async function getToken() {
    if (!LIVE || !AUTH || AUTH.demo) return null;
    if (AUTH.expires_at * 1000 > Date.now() + 60000) return AUTH.access_token;
    if (!refreshing) {
      refreshing = authReq("token?grant_type=refresh_token", { body: { refresh_token: AUTH.refresh_token } })
        .then((d) => { setAuth({ ...AUTH, access_token: d.access_token, refresh_token: d.refresh_token, expires_at: Number(d.expires_at) || Math.floor(Date.now() / 1000) + Number(d.expires_in || 3600) }); })
        .catch(() => setAuth(null))
        .finally(() => { refreshing = null; });
    }
    await refreshing;
    return AUTH ? AUTH.access_token : null;
  }
  const liveAuth = {
    async signUp(username, email, password) {
      if (!(await rpc("username_available", { p_name: username }))) throw authError("username_taken");
      const data = await authReq("signup?redirect_to=" + encodeURIComponent(SITE_URL), { body: { email, password, data: { username } } });
      if (data.access_token) { await startSession(data); return { confirmed: true }; } // E-Mail-Bestätigung abgeschaltet
      const user = data.user || data;
      if (Array.isArray(user.identities) && user.identities.length === 0) throw authError("email_exists");
      return { confirmed: false };
    },
    async signIn(email, password) { await startSession(await authReq("token?grant_type=password", { body: { email, password } })); },
    async signOut() { const t = AUTH && AUTH.access_token; setAuth(null); if (t) authReq("logout", { token: t }).catch(() => {}); },
    async recover(email) { await authReq("recover?redirect_to=" + encodeURIComponent(SITE_URL), { body: { email } }); },
    async updatePassword(password) { const t = await getToken(); if (!t) throw authError("not_logged_in"); await authReq("user", { method: "PUT", body: { password }, token: t }); },
  };
  // Rückkehr aus der Bestätigungs- oder Passwort-E-Mail: Supabase hängt die Anmeldung an die Adresse (#access_token=…)
  async function handleAuthRedirect() {
    const h = location.hash;
    if (!/access_token=|error_description=/.test(h)) return null;
    const p = new URLSearchParams(h.replace(/^#\/?/, ""));
    history.replaceState(null, "", location.pathname + location.search + "#/");
    if (p.get("error_description")) return { error: p.get("error_code") || "link_invalid" };
    const data = { access_token: p.get("access_token"), refresh_token: p.get("refresh_token"), expires_at: p.get("expires_at"), expires_in: p.get("expires_in") };
    try { data.user = await authReq("user", { method: "GET", token: data.access_token }); } catch (e) { return { error: "link_invalid" }; }
    await startSession(data);
    return { type: p.get("type") };
  }

  /* ───────── Live-API (Supabase) ───────── */
  async function rpc(fn, args, retried) {
    const key = CFG.supabaseAnonKey;
    const headers = { "Content-Type": "application/json", apikey: key };
    const token = await getToken();
    if (token) headers.Authorization = "Bearer " + token;          // angemeldet: Konto mitschicken
    else if (key.startsWith("eyJ")) headers.Authorization = "Bearer " + key; // alte JWT-Keys
    let res;
    try {
      res = await fetch(CFG.supabaseUrl.replace(/\/$/, "") + "/rest/v1/rpc/" + fn, { method: "POST", headers, body: JSON.stringify(args) });
    } catch (e) { const err = new Error("network"); err.code = "network"; throw err; }
    const data = await res.json().catch(() => null);
    if (res.status === 401 && token && !retried) { setAuth(null); return rpc(fn, args, true); } // abgelaufene Anmeldung: als Gast weiter
    if (!res.ok) { const err = new Error((data && data.message) || "request_failed"); err.code = data && data.message; err.details = data && data.details; throw err; }
    return data;
  }
  const fromRow = (r) => ({
    id: Number(r.id), text: r.body, cat: r.category_slug, author: r.author_name, created: r.created_at,
    up: r.up_count, down: r.down_count, score: r.score ?? wilson(r.up_count, r.down_count),
    own: !!r.is_own, myVote: r.my_vote || 0, reports: r.report_count || 0, status: r.status || "visible",
  });
  const liveApi = {
    async ranking(range, cat, limit, offset) { return (await rpc("get_ranking", { p_device: DEVICE, p_range: range, p_category: cat, p_limit: limit, p_offset: offset })).map(fromRow); },
    async joke(id) { const rows = await rpc("get_joke", { p_device: DEVICE, p_id: id }); return rows.length ? fromRow(rows[0]) : null; },
    async unrated(exclude) { return (await rpc("get_unrated", { p_device: DEVICE, p_exclude: exclude, p_limit: 10 })).map(fromRow); },
    async similar(text) { const rows = await rpc("find_similar", { p_body: text }); return rows.length ? { id: Number(rows[0].id), text: rows[0].body, match: rows[0].match } : null; },
    async vote(id, value) { const rows = await rpc("cast_vote", { p_device: DEVICE, p_joke: id, p_value: value }); return { up: rows[0].up_count, down: rows[0].down_count }; },
    async post(cat, text, challenge) {
      const args = { p_device: DEVICE, p_category: cat, p_body: text };
      if (challenge) args.p_challenge = challenge;
      try { return Number(await rpc("post_joke", args)); }
      catch (e) { if (e.code === "duplicate") e.duplicateId = Number(e.details); throw e; }
    },
    async report(id) { await rpc("report_joke", { p_device: DEVICE, p_joke: id }); },
    async adminCheck(key) { return rpc("admin_check", { p_key: key }); },
    async adminList(key, view) { return (await rpc("admin_list", { p_key: key, p_view: view })).map(fromRow); },
    async adminSet(key, id, status) { await rpc("admin_set_status", { p_key: key, p_joke: id, p_status: status }); },
    // Erweiterung
    async daily(limit) { return (await rpc("get_daily", { p_device: DEVICE, p_limit: limit })).map((r) => ({ ...fromRow(r), day: r.day })); },
    async reactions(ids) {
      if (!ids.length) return {};
      const out = {};
      for (const r of await rpc("get_reactions", { p_device: DEVICE, p_ids: ids })) out[Number(r.joke_id)] = { lol: r.lol, sigh: r.sigh, dead: r.dead, mine: r.mine || null };
      return out;
    },
    async react(id, kind) { await rpc("set_reaction", { p_device: DEVICE, p_joke: id, p_kind: kind || "" }); },
    async reactionTop(kind, limit) { return (await rpc("get_reaction_top", { p_device: DEVICE, p_kind: kind, p_limit: limit })).map((r) => ({ ...fromRow(r), n: r.n })); },
    async duel() { return (await rpc("get_duel", { p_device: DEVICE })).map(fromRow); },
    async duelVote(winner, loser) { await rpc("cast_duel", { p_device: DEVICE, p_winner: winner, p_loser: loser }); },
    async duelRanking(limit) { return (await rpc("get_duel_ranking", { p_device: DEVICE, p_limit: limit })).map((r) => ({ ...fromRow(r), elo: r.elo, duels: r.duels })); },
    async authors(range) { return rpc("get_author_ranking", { p_range: range, p_limit: 30 }); },
    async profile(name) { const rows = await rpc("get_profile", { p_name: name }); return rows.length ? rows[0] : null; },
    async profileJokes(name) { return (await rpc("get_profile_jokes", { p_device: DEVICE, p_name: name, p_limit: 50, p_offset: 0 })).map(fromRow); },
    async highlights() { return AUTH ? rpc("my_highlights", {}) : []; },
    async challenges() { return rpc("get_challenges", {}); },
    async challengeRanking(id) { return (await rpc("get_challenge_ranking", { p_device: DEVICE, p_challenge: id, p_limit: 50 })).map(fromRow); },
    async adminStats(key, days) { return rpc("admin_stats", { p_key: key, p_days: days }); },
    async adminTotals(key) { return (await rpc("admin_totals", { p_key: key }))[0]; },
    async adminCatStats(key) { return rpc("admin_category_stats", { p_key: key }); },
    async adminBulkAdd(key, cat, bodies, perDay) { return (await rpc("admin_bulk_add", { p_key: key, p_category: cat, p_bodies: bodies, p_per_day: perDay }))[0]; },
    async adminSaveChallenge(key, c) { return rpc("admin_save_challenge", { p_key: key, p_id: c.id || null, p_title: c.title, p_description: c.description, p_starts: c.starts, p_ends: c.ends }); },
  };

  /* ───────── Demo-API (nur Browser) ───────── */
  function mulberry(a) { return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  const demo = (() => {
    const rnd = mulberry(20261015);
    const authors = ["kalauerkönig", "mia_lacht", "bytebert", "montagsmuffel", "pointenpaul", "fritzchen_fan", "lena.lol", "witzbold42", "lachsack", "frau_flach"];
    // Tägliche Auswahl: Jeder Witz hat einen festen Tag in einem 30-Tage-Zyklus.
    // So erscheinen jeden Tag rund 12 „neue“ Witze unter „Heute“, egal wann jemand die Seite öffnet.
    const PERIOD = 30, DAY = 864e5, now = Date.now();
    const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
    const today0 = midnight.getTime();
    const dayIdx = Math.round((today0 - midnight.getTimezoneOffset() * 6e4) / DAY);
    const seed = [];
    let id = 1, k = 0;
    for (const [cat, list] of Object.entries(window.STARTWITZE || {})) for (const text of list) {
      const slot = (k++ * 7 + 3) % PERIOD;                 // gleichmäßig über die 30 Tage verteilt
      const ageDays = (((dayIdx - slot) % PERIOD) + PERIOD) % PERIOD;
      const hour = rnd(), rate = 3 + rnd() * 45, ratio = 0.5 + rnd() * 0.46;
      const created = ageDays === 0 ? today0 + hour * (now - today0) : today0 - ageDays * DAY + hour * DAY;
      const n = Math.floor(((now - created) / DAY) * rate);
      const up = Math.round(n * ratio);
      seed.push({ id: id++, cat, text, author: authors[Math.floor(rnd() * authors.length)], created: new Date(created).toISOString(), up, down: n - up, status: "visible", reports: 0 });
    }
    const base = now;
    seed.push({ id: id++, cat: "flachwitze", text: "GRATIS FOLLOWER!!! Klick auf meinen Kanal, 1000 Abos in 24 Stunden", author: "promo_profi", created: new Date(base - 3 * 36e5).toISOString(), up: 0, down: 6, status: "hidden", reports: 4 });
    const st = { votes: store.get("demo_votes", {}), posted: store.get("demo_posted", []), mod: store.get("demo_mod", {}), reported: store.get("demo_reported", []),
      reacts: store.get("demo_reacts", {}), duels: store.get("demo_duels", {}), elo: store.get("demo_elo", {}), duelCount: store.get("demo_duelcount", {}) };
    const save = () => { store.set("demo_votes", st.votes); store.set("demo_posted", st.posted); store.set("demo_mod", st.mod); store.set("demo_reported", st.reported);
      store.set("demo_reacts", st.reacts); store.set("demo_duels", st.duels); store.set("demo_elo", st.elo); store.set("demo_duelcount", st.duelCount); };
    const all = () => [...st.posted, ...seed].map((j) => {
      const m = st.mod[j.id] || {}, v = st.votes[j.id] || 0;
      const up = j.up + (v === 1 ? 1 : 0), down = j.down + (v === -1 ? 1 : 0);
      return { ...j, status: m.status || j.status, reports: m.reports ?? j.reports, reviewed: !!m.reviewed, up, down, score: wilson(up, down), own: j.device === DEVICE, myVote: v };
    });
    const visible = (j) => j.status === "visible" && !st.reported.includes(j.id);
    const ageH = (j) => (Date.now() - new Date(j.created).getTime()) / 36e5;
    const fail = (code) => { const e = new Error(code); e.code = code; return e; };
    const wait = (v) => new Promise((r) => setTimeout(() => r(v), 60));
    return {
      ranking(range, cat, limit, offset) {
        const h = range === "day" ? 24 : range === "week" ? 168 : Infinity;
        return wait(all().filter((j) => visible(j) && ageH(j) < h && (!cat || j.cat === cat) && (range !== "all" || j.up + j.down >= 20))
          .sort((a, b) => b.score - a.score || b.up + b.down - (a.up + a.down)).slice(offset, offset + limit));
      },
      joke(id) { return wait(all().find((j) => j.id === id && visible(j)) || null); },
      unrated(exclude) {
        return wait(all().filter((j) => visible(j) && !j.own && !j.myVote && !exclude.includes(j.id))
          .map((j) => ({ j, k: (j.up + j.down >= 20 ? 2 : 0) + (ageH(j) > 168 ? 1 : 0), r: Math.random() }))
          .sort((a, b) => a.k - b.k || a.r - b.r).slice(0, 10).map((x) => x.j));
      },
      similar(text) {
        let best = null;
        for (const j of all()) { if (j.status !== "visible") continue; const s = similarity(text, j.text); if (s >= DUP_THRESHOLD && (!best || s > best.match)) best = { id: j.id, text: j.text, match: s }; }
        return wait(best);
      },
      vote(id, value) {
        const j = all().find((x) => x.id === id);
        if (!j || !visible(j)) return Promise.reject(fail("joke_not_found"));
        if (j.own) return Promise.reject(fail("own_joke"));
        if (value === 0) delete st.votes[id]; else st.votes[id] = value;
        save();
        const n = all().find((x) => x.id === id);
        return wait({ up: n.up, down: n.down });
      },
      async post(cat, text, challenge) {
        if (!AUTH) throw fail("not_logged_in");
        const name = AUTH.username;
        const dup = await this.similar(text);
        if (dup) { const e = fail("duplicate"); e.duplicateId = dup.id; throw e; }
        const id = Date.now();
        st.posted.unshift({ id, cat, text, author: name, created: new Date().toISOString(), up: 0, down: 0, status: "visible", reports: 0, device: DEVICE, challenge: challenge || null });
        save();
        return id;
      },
      report(id) {
        const j = all().find((x) => x.id === id); if (!j) return wait();
        const reports = j.reports + 1, limit = j.reviewed ? 10 : 3;
        st.mod[id] = { ...(st.mod[id] || {}), reports, status: reports >= limit ? "hidden" : j.status };
        st.reported.push(id); save(); return wait();
      },
      adminCheck(key) { return wait(key === DEMO_ADMIN_KEY); },
      adminList(key, view) {
        if (key !== DEMO_ADMIN_KEY) return Promise.reject(fail("not_admin"));
        const list = view === "neu"
          ? all().filter((j) => j.status === "visible").sort((a, b) => new Date(b.created) - new Date(a.created)).slice(0, 50)
          : all().filter((j) => j.status === "hidden" || (j.status === "visible" && j.reports > 0)).sort((a, b) => (a.status === "hidden" ? 0 : 1) - (b.status === "hidden" ? 0 : 1) || b.reports - a.reports);
        return wait(list);
      },
      adminSet(key, id, status) {
        if (key !== DEMO_ADMIN_KEY) return Promise.reject(fail("not_admin"));
        st.mod[id] = status === "visible" ? { status: "visible", reports: 0, reviewed: true } : { ...(st.mod[id] || {}), status: "removed" };
        st.reported = st.reported.filter((x) => x !== id || status !== "visible");
        save(); return wait();
      },
      // ── Erweiterung (Demo: alles nur in diesem Browser) ──
      daily(limit) {
        const out = [], used = new Set(), list = all().filter(visible);
        const end0 = new Date(); end0.setHours(20, 0, 0, 0);
        if (Date.now() < end0.getTime()) end0.setDate(end0.getDate() - 1);
        for (let k = 0; k < Math.min(limit, 14); k++) {
          const end = end0.getTime() - k * DAY, start = end - DAY;
          const best = list.filter((j) => !used.has(j.id) && j.up > 0 && new Date(j.created).getTime() > start && new Date(j.created).getTime() <= end).sort((a, b) => b.score - a.score)[0];
          if (!best) continue;
          used.add(best.id);
          const d = new Date(end); out.push({ ...best, day: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` });
        }
        return wait(out);
      },
      reactions(ids) {
        const out = {};
        for (const id of ids) {
          const r = mulberry(id * 7919), mine = st.reacts[id] || null;
          const c = { lol: Math.floor(r() * 9), sigh: Math.floor(r() * 4), dead: Math.floor(r() * 3) };
          if (mine) c[mine]++;
          out[id] = { ...c, mine };
        }
        return wait(out);
      },
      react(id, kind) { if (kind) st.reacts[id] = kind; else delete st.reacts[id]; save(); return wait(); },
      async reactionTop(kind, limit) {
        const list = all().filter((j) => visible(j) && ageH(j) < 168);
        const counts = await this.reactions(list.map((j) => j.id));
        return list.map((j) => ({ ...j, n: counts[j.id][kind] })).filter((j) => j.n > 0).sort((a, b) => b.n - a.n).slice(0, limit);
      },
      duel() {
        const list = all().filter((j) => visible(j) && !j.own);
        const a = list[Math.floor(Math.random() * list.length)];
        const rest = list.filter((j) => j.id !== a.id && !st.duels[[Math.min(a.id, j.id), Math.max(a.id, j.id)].join("-")]);
        const b = rest[Math.floor(Math.random() * rest.length)];
        return wait(a && b ? [a, b] : []);
      },
      duelVote(w, l) {
        const key = [Math.min(w, l), Math.max(w, l)].join("-");
        if (st.duels[key]) return wait();
        st.duels[key] = w;
        const ew = st.elo[w] || 1000, el = st.elo[l] || 1000, e = 1 / (1 + Math.pow(10, (el - ew) / 400));
        st.elo[w] = ew + 24 * (1 - e); st.elo[l] = el - 24 * (1 - e);
        st.duelCount[w] = (st.duelCount[w] || 0) + 1; st.duelCount[l] = (st.duelCount[l] || 0) + 1;
        save(); return wait();
      },
      duelRanking(limit) {
        return wait(all().filter((j) => visible(j) && st.duelCount[j.id]).map((j) => ({ ...j, elo: Math.round(st.elo[j.id]), duels: st.duelCount[j.id] }))
          .sort((a, b) => b.elo - a.elo).slice(0, limit));
      },
      authors(range) {
        const by = {};
        for (const j of all()) {
          if (!visible(j) || (range === "week" && ageH(j) > 168)) continue;
          const a = (by[j.author] = by[j.author] || { username: j.author, jokes: 0, up_count: 0, down_count: 0 });
          a.jokes++; a.up_count += j.up; a.down_count += j.down;
        }
        return wait(Object.values(by).filter((a) => a.up_count + a.down_count >= (range === "all" ? 20 : 5))
          .map((a) => ({ ...a, score: wilson(a.up_count, a.down_count) })).sort((a, b) => b.score - a.score).slice(0, 30));
      },
      async profile(name) {
        const mine = all().filter((j) => visible(j) && j.author.toLowerCase() === name.toLowerCase());
        if (!mine.length && !(AUTH && AUTH.username.toLowerCase() === name.toLowerCase())) return null;
        const daily = await this.daily(14), today = await this.ranking("day", null, 100, 0);
        const rank = today.findIndex((j) => j.author.toLowerCase() === name.toLowerCase());
        return {
          username: mine[0] ? mine[0].author : AUTH.username, member_since: null, jokes: mine.length,
          up_count: mine.reduce((s, j) => s + j.up, 0), down_count: mine.reduce((s, j) => s + j.down, 0),
          top_up: Math.max(0, ...mine.map((j) => j.up)), crowns: daily.filter((d) => d.author.toLowerCase() === name.toLowerCase()).length,
          challenge_wins: 0, best_rank: rank < 0 ? null : rank + 1,
        };
      },
      profileJokes(name) { return wait(all().filter((j) => visible(j) && j.author.toLowerCase() === name.toLowerCase()).sort((a, b) => b.score - a.score).slice(0, 50)); },
      highlights() { return wait([]); },
      challenges() {
        const end = new Date(); end.setHours(20, 0, 0, 0); end.setDate(end.getDate() + ((7 - end.getDay()) % 7));
        if (end.getTime() <= Date.now()) end.setDate(end.getDate() + 7);
        return wait([{ id: 1, title: "Witze übers Fitnessstudio", description: "Hanteln, Laufband, Neujahrsvorsätze: Dein bester Witz rund ums Training.",
          starts_at: new Date(Date.now() - DAY).toISOString(), ends_at: end.toISOString(), active: true, entries: st.posted.filter((j) => j.challenge === 1).length, winner_name: null, winner_joke: null }]);
      },
      challengeRanking(id) { return wait(all().filter((j) => visible(j) && j.challenge === id).sort((a, b) => b.score - a.score)); },
      adminStats(key, days) {
        if (key !== DEMO_ADMIN_KEY) return Promise.reject(fail("not_admin"));
        return wait(Array.from({ length: days }, (_, i) => { const d = new Date(Date.now() - (days - 1 - i) * DAY); const r = mulberry(d.getDate()); return { day: d.toISOString().slice(0, 10), votes: Math.floor(r() * 300), voters: Math.floor(r() * 60), reactions: Math.floor(r() * 80), duels: Math.floor(r() * 120), new_jokes: Math.floor(r() * 6), signups: Math.floor(r() * 3) }; }));
      },
      adminTotals(key) {
        if (key !== DEMO_ADMIN_KEY) return Promise.reject(fail("not_admin"));
        const l = all(); return wait({ jokes: l.filter(visible).length, user_jokes: st.posted.length, users: Object.keys(store.get("demo_accounts", {})).length, votes: Object.keys(st.votes).length, devices: 1, queued: 0, queue_until: null });
      },
      adminCatStats(key) {
        if (key !== DEMO_ADMIN_KEY) return Promise.reject(fail("not_admin"));
        return wait(Object.entries(CATS).map(([slug, name]) => ({ slug, name, jokes: all().filter((j) => visible(j) && j.cat === slug).length, queued: 0, votes_week: 0 })));
      },
      adminBulkAdd(key) { return key !== DEMO_ADMIN_KEY ? Promise.reject(fail("not_admin")) : Promise.reject(fail("demo_only")); },
      adminSaveChallenge(key) { return key !== DEMO_ADMIN_KEY ? Promise.reject(fail("not_admin")) : Promise.reject(fail("demo_only")); },
    };
  })();

  // Demo-Konten: nur in diesem Browser, kein echtes Konto und kein gespeichertes Passwort
  const demoAuth = {
    async signUp(username, email) {
      const accts = store.get("demo_accounts", {});
      if (Object.values(accts).some((a) => a.username.toLowerCase() === username.toLowerCase())) throw authError("username_taken");
      if (accts[email.toLowerCase()]) throw authError("email_exists");
      accts[email.toLowerCase()] = { username };
      store.set("demo_accounts", accts);
      setAuth({ demo: true, email, username });
      return { confirmed: true };
    },
    async signIn(email) {
      const a = store.get("demo_accounts", {})[email.toLowerCase()];
      if (!a) throw authError("invalid_credentials");
      setAuth({ demo: true, email, username: a.username });
    },
    async signOut() { setAuth(null); },
    async recover() {},
    async updatePassword() {},
  };

  const API = LIVE ? liveApi : demo;
  const AUTH_API = LIVE ? liveAuth : demoAuth;

  /* ───────── Zustand & Navigation ───────── */
  const S = {
    range: "day", cat: null, shown: PAGE, rows: [], hasMore: false, detail: null,
    queue: [], seen: new Set(), rated: 0, swipeLoading: false, swipeDone: false,
    adminKey: session.get("admin"), adminView: "gemeldet",
    hiddenForMe: new Set(store.get("hidden", [])),
    react: {}, challenges: null, hl: [], daily: null, authorRange: "week", editChallenge: null,
  };
  let renderToken = 0;

  function route() {
    const h = location.hash.replace(/^#\/?/, "");
    if (h.startsWith("witz/")) return { view: "detail", id: Number(h.slice(5)) };
    if (h === "bewerten") return { view: "swipe" };
    if (h === "duell") return { view: "duel" };
    if (h === "highlights") return { view: "highlights" };
    if (h === "autoren") return { view: "authors" };
    if (h === "challenge") return { view: "challenge" };
    if (h.startsWith("kategorie/")) return { view: "list", cat: h.slice(10) };
    if (h.startsWith("u/")) { let n = h.slice(2); try { n = decodeURIComponent(n); } catch (e) { /* roh lassen */ } return { view: "profile", name: n }; }
    if (h === "admin") return { view: "admin" };
    return { view: "list" };
  }
  function renderNav(view) {
    const items = [["#/", "list", "Bestenliste"], ["#/bewerten", "swipe", "Bewerten"], ["#/duell", "duel", "Duell"], ["#/highlights", "highlights", "Highlights"], ["#/autoren", "authors", "Autoren"]];
    if (S.adminKey || view === "admin") items.push(["#/admin", "admin", "Moderation"]);
    $("#nav").innerHTML = items.map(([href, v, l]) => `<a href="${href}" ${view === v ? 'aria-current="page"' : ""}>${l}</a>`).join("");
    $("#listControls").style.display = view === "list" ? "grid" : "none";
    $("#postBtn").hidden = view === "swipe" || view === "admin" || view === "duel";
    const cur = document.querySelector('.nav [aria-current="page"]'); if (cur && cur.scrollIntoView) cur.scrollIntoView({ block: "nearest", inline: "nearest" });
    $("#who").textContent = AUTH ? "@" + (AUTH.username || "Konto") : "Anmelden";
    $("#who").title = AUTH ? "Dein Konto" : "Anmelden oder registrieren (nur zum Posten nötig)";
  }
  function renderChips() {
    $("#chips").innerHTML = [[null, "Alle"], ...Object.entries(CATS)].map(([k, v]) => `<button class="chip" aria-pressed="${k === S.cat}" data-cat="${k || ""}">${v}</button>`).join("");
  }
  async function render() {
    const r = route(), token = ++renderToken;
    if (r.cat && CATS[r.cat] && S.cat !== r.cat) { S.cat = r.cat; S.rows = []; renderChips(); }
    renderNav(r.view);
    try {
      if (r.view === "list") await renderList(token);
      else if (r.view === "swipe") await renderSwipe(token);
      else if (r.view === "detail") await renderDetail(token, r.id);
      else if (r.view === "duel") await renderDuel(token);
      else if (r.view === "highlights") await renderHighlights(token);
      else if (r.view === "authors") await renderAuthors(token);
      else if (r.view === "profile") await renderProfile(token, r.name);
      else if (r.view === "challenge") await renderChallenge(token);
      else await renderAdmin(token);
    } catch (e) {
      if (token !== renderToken) return;
      console.error(e);
      $("#main").innerHTML = `<div class="view"><p class="empty">${esc(errorText(e))}<br><button class="btn ghost" data-retry style="margin-top:12px">Erneut laden</button></p></div>`;
    }
  }
  const stale = (token) => token !== renderToken;

  /* ───────── Karten ───────── */
  const ICON_UP = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>';
  const ICON_DOWN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M19 12l-7 7-7-7"/></svg>';
  function cardHtml(j, rank, badge) {
    const n = j.up + j.down, pct = Math.round((j.up / Math.max(n, 1)) * 100), single = rank == null;
    const dis = j.own ? ' disabled title="Eigene Witze kannst du nicht bewerten"' : "";
    return `<li class="card${single ? " single" : ""}${!single && rank <= 3 ? " top" : ""}" data-card="${j.id}">
      ${single ? "" : `<div class="rank">${rank}${badge ? `<small>${badge}</small>` : ""}</div>`}
      <div class="body"><div class="tag">${CATS[j.cat] || ""}</div>
        ${single ? `<p class="joke">${esc(j.text)}</p>` : `<a class="joke" href="#/witz/${j.id}">${esc(j.text)}</a>`}</div>
      <div class="foot">
        <button class="vote up" data-vote="1" data-id="${j.id}" aria-pressed="${j.myVote === 1}" aria-label="Gefällt mir"${dis}>${ICON_UP}${fmt(j.up)}</button>
        <button class="vote down" data-vote="-1" data-id="${j.id}" aria-pressed="${j.myVote === -1}" aria-label="Gefällt mir nicht"${dis}>${ICON_DOWN}${fmt(j.down)}</button>
        <span class="score">${n ? pct + " % Lacher" : "noch keine Stimmen"}<br>Score ${(j.score * 100).toFixed(1)}</span>
      </div>
      <div class="meter"><i style="width:${pct}%"></i></div>
      <div class="reacts" data-reacts="${j.id}">${reactsHtml(j)}</div>
      <div class="by"><span>${authorLink(j.author)} · ${ago(j.created)}${j.own ? " · dein Witz" : ""}</span>
        <span class="by-actions">${single ? "" : `<a class="link" href="#/witz/${j.id}">Teilen</a>`}${j.own ? "" : `<button class="link" data-report="${j.id}">Melden</button>`}</span></div>
    </li>`;
  }

  function authorLink(name) {
    return name === "Lachwerk" ? "@Lachwerk" : `<a class="author" href="#/u/${encodeURIComponent(name)}">@${esc(name)}</a>`;
  }
  const REACTS = [["lol", "😂", "Zum Brüllen"], ["sigh", "🙄", "Seufz"], ["dead", "💀", "Rabenschwarz"]];
  function reactsHtml(j) {
    const r = S.react[j.id] || { lol: 0, sigh: 0, dead: 0, mine: null };
    return REACTS.map(([k, emo, label]) => `<button class="react" data-react="${k}" data-id="${j.id}" aria-pressed="${r.mine === k}" aria-label="${label}" title="${label}"${j.own ? " disabled" : ""}><span aria-hidden="true">${emo}</span>${r[k] ? fmt(r[k]) : ""}</button>`).join("");
  }
  async function loadReactions(list) {
    const ids = list.map((j) => j.id).filter((id) => !(id in S.react));
    if (!ids.length) return;
    try {
      const got = await API.reactions(ids);
      for (const id of ids) S.react[id] = got[id] || { lol: 0, sigh: 0, dead: 0, mine: null };
      for (const j of list) { const el = document.querySelector(`[data-reacts="${j.id}"]`); if (el) el.innerHTML = reactsHtml(j); }
    } catch (e) { /* Reaktionen sind Beiwerk */ }
  }
  async function react(id, kind, j) {
    const r = S.react[id] || { lol: 0, sigh: 0, dead: 0, mine: null };
    const prev = { ...r };
    const next = r.mine === kind ? null : kind;
    if (r.mine) r[r.mine] = Math.max(0, r[r.mine] - 1);
    if (next) r[next]++;
    r.mine = next; S.react[id] = r;
    const el = document.querySelector(`[data-reacts="${id}"]`); if (el && j) el.innerHTML = reactsHtml(j);
    try { await API.react(id, next); markActivity(); }
    catch (e) { S.react[id] = prev; if (el && j) el.innerHTML = reactsHtml(j); toast(errorText(e)); }
  }

  /* ───────── Bestenliste ───────── */
  async function renderList(token) {
    if (!S.rows.length) $("#main").innerHTML = '<p class="loading">Lade Bestenliste …</p>';
    let rows = await API.ranking(S.range, S.cat, S.shown + 1, 0);
    S.fallback = null;
    // Noch nichts los? Dann die Besten des nächstgrößeren Zeitraums zeigen statt einer leeren Seite.
    for (const wider of S.range === "day" ? ["week", "all"] : S.range === "week" ? ["all"] : []) {
      if (rows.length) break;
      rows = await API.ranking(wider, S.cat, S.shown + 1, 0);
      if (rows.length) S.fallback = wider;
    }
    if (stale(token)) return;
    S.hasMore = rows.length > S.shown;
    S.rows = rows.slice(0, S.shown).filter((j) => !S.hiddenForMe.has(j.id));
    drawList();
    loadReactions(S.rows);
    loadChallenge().then(() => { if (!stale(token)) drawListBanners(); });
    loadHighlights().then(() => { if (!stale(token)) drawListBanners(); });
  }
  function drawList() {
    const r = RANGES[S.fallback || S.range];
    const fallbackNote = S.fallback
      ? `<div class="notice">${S.range === "day" ? "Heute gibt es noch keine neuen Witze." : "Diese Woche gibt es noch keine neuen Witze."} Hier sind die ${S.fallback === "week" ? "Besten der Woche" : "Besten aller Zeiten"}. Poste den ersten von heute!</div>`
      : "";
    $("#main").innerHTML = `<div class="view">
      <div id="listBanners" class="banners">${bannersHtml()}</div>
      <a class="cta" href="#/bewerten"><span><strong>Neue Witze bewerten</strong><br>Wisch dich durch frische Einsendungen und entscheide mit, wer nach oben kommt.</span><span class="arrow" aria-hidden="true">→</span></a>
      ${fallbackNote}
      <div class="meta-row"><span>${r.label}</span><span>${S.rows.length === 1 ? "1 Witz" : S.rows.length + (S.hasMore ? "+" : "") + " Witze"}</span></div>
      ${S.rows.length ? `<ol class="list">${S.rows.map((j, i) => cardHtml(j, i + 1, i === 0 ? r.best : "")).join("")}</ol>`
        : `<p class="empty">${S.range === "all" ? "Noch hat kein Witz 20 Stimmen. Hilf mit und bewerte neue Witze!" : "Hier gibt es noch keine Witze. Poste den ersten!"}</p>`}
      ${S.hasMore ? '<button class="btn ghost more" data-more>Weitere Witze</button>' : ""}
      <section class="how"><h2>So funktioniert das Ranking</h2>
        <p>Sortiert wird nach dem Wilson-Score: der vorsichtigen Schätzung, wie viel Prozent aller Leser den Witz mögen. Ein Witz mit 4 von 4 Likes landet deshalb hinter einem mit 180 von 200.</p>
        <p>„Heute“ zeigt Witze der letzten 24 Stunden, „Woche“ der letzten 7 Tage. Für „Alltime“ braucht ein Witz mindestens 20 Stimmen.</p></section>
    </div>`;
  }

  /* ───────── Abstimmen (sofort anzeigen, bei Fehler zurück) ───────── */
  function findRow(id) { return S.rows.find((j) => j.id === id) || (S.detail && S.detail.id === id ? S.detail : null); }
  async function vote(id, value) {
    const j = findRow(id); if (!j || j.own) return;
    const prev = { up: j.up, down: j.down, myVote: j.myVote };
    const next = j.myVote === value ? 0 : value;
    if (j.myVote === 1) j.up--; if (j.myVote === -1) j.down--;
    if (next === 1) j.up++; if (next === -1) j.down++;
    j.myVote = next; j.score = wilson(j.up, j.down);
    redrawCard(j);
    try { const r = await API.vote(id, next); j.up = r.up; j.down = r.down; j.score = wilson(j.up, j.down); redrawCard(j); if (next) markActivity(); }
    catch (e) { Object.assign(j, prev); j.score = wilson(j.up, j.down); redrawCard(j); toast(errorText(e)); }
  }
  function redrawCard(j) {
    const el = document.querySelector(`[data-card="${j.id}"]`); if (!el) return;
    const single = el.classList.contains("single");
    const rank = single ? null : S.rows.indexOf(j) + 1;
    el.outerHTML = cardHtml(j, rank, rank === 1 ? RANGES[S.range].best : "");
  }

  /* ───────── Swipe-Modus ───────── */
  let refillPromise = null;
  function refill() {
    if (S.swipeDone) return Promise.resolve();
    if (refillPromise) return refillPromise;
    refillPromise = (async () => {
      const exclude = [...S.seen, ...S.queue.map((j) => j.id)];
      const more = (await API.unrated(exclude)).filter((j) => !exclude.includes(j.id) && !S.hiddenForMe.has(j.id));
      if (!more.length) S.swipeDone = true;
      S.queue.push(...more);
    })().finally(() => { refillPromise = null; });
    return refillPromise;
  }
  async function renderSwipe(token) {
    if (S.queue.length < 3 && !S.swipeDone) {
      if (!S.queue.length) $("#main").innerHTML = '<p class="loading">Lade neue Witze …</p>';
      await refill();
      if (stale(token)) return;
    }
    drawSwipe();
  }
  let drag = null, leaving = false;
  function drawSwipe() {
    const cur = S.queue[0], next = S.queue[1];
    const sn = streakCount();
    const intro = `<div><h1>Neue Witze bewerten</h1><p class="muted">Wisch nach rechts, wenn du lachen musstest, nach links, wenn nicht.${sn >= 2 ? ` <span class="streak-pill">🔥 ${sn} Tage in Folge</span>` : ""}</p></div>`;
    if (!cur) {
      $("#main").innerHTML = `<div class="view">${intro}<div class="swipe-empty"><h2>Alles bewertet!</h2>
        <p class="muted">${S.rated ? `Du hast ${S.rated} ${S.rated === 1 ? "Witz" : "Witze"} bewertet. ` : ""}Gerade gibt es keine neuen Witze für dich.</p>
        <div class="row center"><a class="btn ghost" href="#/">Zur Bestenliste</a><button class="btn accent" data-post>Selbst einen posten</button></div></div></div>`;
      return;
    }
    const n = cur.up + cur.down;
    $("#main").innerHTML = `<div class="view">${intro}
      <div class="swipe-stage">
        ${next ? `<div class="swipe-card behind" aria-hidden="true"><div class="tag">${CATS[next.cat] || ""}</div><p class="swipe-text">${esc(next.text)}</p></div>` : ""}
        <div class="swipe-card" id="swipeCard">
          <span class="stamp like" id="stampLike">Lustig</span><span class="stamp nope" id="stampNope">Nicht lustig</span>
          <div class="tag">${CATS[cur.cat] || ""}</div>
          <p class="swipe-text">${esc(cur.text)}</p>
          <div class="swipe-meta">@${esc(cur.author)} · ${ago(cur.created)} · ${n === 0 ? "noch keine Stimmen" : fmt(n) + " Stimmen"}</div>
        </div>
      </div>
      <div class="swipe-actions">
        <button class="round nope" data-swipe="-1" aria-label="Nicht lustig"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
        <button class="btn ghost" data-swipe="0">Überspringen</button>
        <button class="round like" data-swipe="1" aria-label="Lustig"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></button>
      </div>
      <p class="swipe-hint">${S.rated ? S.rated + " bewertet · " : ""}Tastatur: ← nicht lustig · → lustig · ↓ überspringen</p>
    </div>`;
    const card = $("#swipeCard");
    const setDx = (dx) => {
      card.style.transform = `translateX(${dx}px) rotate(${dx / 18}deg)`;
      $("#stampLike").style.opacity = Math.min(Math.max(dx / 110, 0), 1);
      $("#stampNope").style.opacity = Math.min(Math.max(-dx / 110, 0), 1);
    };
    card.addEventListener("pointerdown", (e) => { if (leaving) return; card.setPointerCapture(e.pointerId); drag = { x: e.clientX, dx: 0 }; card.classList.add("dragging"); });
    card.addEventListener("pointermove", (e) => { if (!drag) return; drag.dx = e.clientX - drag.x; setDx(drag.dx); });
    card.addEventListener("pointerup", () => { if (!drag) return; const dx = drag.dx; drag = null; card.classList.remove("dragging"); if (dx > 110) decide(1); else if (dx < -110) decide(-1); else setDx(0); });
    card.addEventListener("pointercancel", () => { drag = null; card.classList.remove("dragging"); setDx(0); });
  }
  function decide(d) {
    const cur = S.queue[0]; if (!cur || leaving) return;
    leaving = true;
    S.seen.add(cur.id);
    if (d !== 0) {
      S.rated++;
      API.vote(cur.id, d).then(markActivity).catch((e) => toast(errorText(e)));
    }
    const card = $("#swipeCard");
    if (card) {
      if (d === 1) $("#stampLike").style.opacity = 1;
      if (d === -1) $("#stampNope").style.opacity = 1;
      card.classList.add("leaving");
      card.style.transform = d === 0 ? "translateY(-40px) scale(.96)" : `translateX(${d * 130}%) rotate(${d * 14}deg)`;
    }
    setTimeout(() => {
      S.queue.shift(); leaving = false;
      if (route().view !== "swipe") return;
      const needsMore = S.queue.length < 3 && !S.swipeDone;
      const wasEmpty = !S.queue.length;
      if (wasEmpty && needsMore) $("#main").innerHTML = '<p class="loading">Lade neue Witze …</p>';
      else drawSwipe();
      if (needsMore) refill().then(() => { if (wasEmpty && route().view === "swipe") drawSwipe(); }).catch((e) => toast(errorText(e)));
    }, 230);
  }

  /* ───────── Witz-Seite & Teilen ───────── */
  const shareUrl = (id) => location.href.split("#")[0] + "#/witz/" + id;
  async function renderDetail(token, id) {
    $("#main").innerHTML = '<p class="loading">Lade Witz …</p>';
    const j = await API.joke(id);
    if (stale(token)) return;
    S.detail = j;
    if (!j || S.hiddenForMe.has(j.id)) {
      $("#main").innerHTML = `<div class="view"><p class="empty">Diesen Witz gibt es nicht (mehr).</p><a class="btn ghost" href="#/">Zur Bestenliste</a></div>`;
      return;
    }
    if (!S.daily) { try { S.daily = await API.daily(30); } catch (e) { S.daily = []; } if (stale(token)) return; }
    const crown = S.daily.find((d) => d.id === j.id);
    j.label = crown ? "Witz des Tages · " + fmtDay(crown.day) : null;
    const url = shareUrl(j.id);
    const wa = "https://wa.me/?text=" + encodeURIComponent(j.text + "\n\nMehr davon: " + url);
    $("#main").innerHTML = `<div class="view">
      <div><a class="link" href="#/" style="font-size:.88rem">← Zur Bestenliste</a></div>
      ${crown ? `<div class="crown-badge">👑 Witz des Tages am ${fmtDay(crown.day)}</div>` : ""}
      <ol class="list">${cardHtml(j)}</ol>
      <section class="share" aria-label="Teilen">
        <h2>Witz teilen</h2>
        <div class="share-grid">
          <div class="share-buttons">
            <a class="btn wa" href="${wa}" target="_blank" rel="noopener noreferrer">Per WhatsApp schicken</a>
            <button class="btn ghost" data-share-image>Als Bild teilen</button>
            <button class="btn ghost" data-share-link>Link teilen</button>
            <p class="muted small" id="shareMsg" role="status"></p>
          </div>
          <canvas id="storyCanvas" aria-label="Vorschau des Story-Bilds"></canvas>
        </div>
      </section>
      <div class="row"><button class="btn ghost" data-morecat="${j.cat}">Mehr ${CATS[j.cat] || ""}</button><a class="btn ghost" href="#/bewerten">Neue Witze bewerten</a></div>
    </div>`;
    drawStory($("#storyCanvas"), j);
    loadReactions([j]);
  }

  function wrapLines(c, text, maxW) {
    const out = [];
    for (const para of text.split("\n")) {
      let line = "";
      for (const w of para.split(/\s+/)) { const t = line ? line + " " + w : w; if (c.measureText(t).width > maxW && line) { out.push(line); line = w; } else line = t; }
      out.push(line);
    }
    return out;
  }
  function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
  function drawStory(canvas, j) {
    const W = 1080, H = 1920, pad = 80, c = canvas.getContext("2d");
    canvas.width = W; canvas.height = H;
    const DISPLAY = getComputedStyle(document.documentElement).getPropertyValue("--f-display");
    const BODY = getComputedStyle(document.documentElement).getPropertyValue("--f-body");
    const host = location.host || "lachwerk";
    c.fillStyle = "#ffc928"; c.fillRect(0, 0, W, H); c.textBaseline = "top";
    const ls = 64, ly = 130;
    c.font = `800 ${ls}px ${DISPLAY}`; c.fillStyle = "#15172a"; c.fillText("Lach", pad, ly);
    const lw = c.measureText("Lach").width, ww = c.measureText("werk").width;
    rr(c, pad + lw + 4, ly - ls * 0.12, ww + ls * 0.36, ls * 1.18, ls * 0.18); c.fill();
    c.fillStyle = "#ffc928"; c.fillText("werk", pad + lw + 4 + ls * 0.18, ly);
    const fs = 38, fy = H - 130 - fs;
    c.font = `600 ${fs}px ${BODY}`; c.fillStyle = "#15172a"; c.fillText("Bewerte ihn auf " + host, pad, fy);
    let top = ly + ls * 1.4 + 60;
    if (j.label) {
      c.font = `800 40px ${DISPLAY}`;
      const t = "👑 " + j.label.toUpperCase(), tw = c.measureText(t).width;
      c.fillStyle = "#15172a"; rr(c, pad, top, tw + 56, 76, 38); c.fill();
      c.fillStyle = "#ffc928"; c.fillText(t, pad + 28, top + 18);
      top += 76 + 40;
    }
    const cp = 60, maxW = W - 2 * pad - 2 * cp, avail = fy - 60 - top;
    let size = 84, lines, lh;
    for (;;) { c.font = `500 ${size}px ${BODY}`; lines = wrapLines(c, j.text, maxW); lh = size * 1.28; if (cp * 2 + 30 + 18 + lines.length * lh + 24 + 30 <= avail || size <= 28) break; size -= 2; }
    const ch = cp * 2 + 30 + 18 + lines.length * lh + 24 + 30, cy = top + Math.max(0, (avail - ch) / 2);
    c.fillStyle = "#15172a"; rr(c, pad, cy + 12, W - 2 * pad, ch, 48); c.fill();
    c.fillStyle = "#ffffff"; rr(c, pad, cy, W - 2 * pad, ch, 48); c.fill();
    let y = cy + cp;
    c.fillStyle = "#5b5f78"; c.font = `600 30px ${BODY}`; c.fillText((CATS[j.cat] || "").toUpperCase(), pad + cp, y);
    y += 48; c.fillStyle = "#15172a"; c.font = `500 ${size}px ${BODY}`;
    for (const l of lines) { c.fillText(l, pad + cp, y); y += lh; }
    y += 24; c.fillStyle = "#5b5f78"; c.font = `500 30px ${BODY}`; c.fillText("@" + j.author, pad + cp, y);
  }
  async function shareImage() {
    const j = S.detail, msg = $("#shareMsg"), canvas = $("#storyCanvas"); if (!j || !canvas) return;
    const blob = await new Promise((r) => canvas.toBlob(r, "image/png"));
    if (!blob) { msg.textContent = "Das Bild konnte nicht erstellt werden."; return; }
    const file = new File([blob], `lachwerk-witz-${j.id}.png`, { type: "image/png" });
    try {
      if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], text: shareUrl(j.id) }); return; }
    } catch (e) { if (e.name === "AbortError") return; }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = file.name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    msg.textContent = "Bild gespeichert. Du kannst es jetzt in deiner Story posten.";
  }
  async function shareLink() {
    const j = S.detail, msg = $("#shareMsg"); if (!j) return;
    const url = shareUrl(j.id);
    if (navigator.share) { try { await navigator.share({ title: "Witz auf Lachwerk", text: j.text, url }); return; } catch (e) { if (e.name === "AbortError") return; } }
    try { await navigator.clipboard.writeText(url); msg.textContent = "Link kopiert."; } catch (e) { msg.textContent = url; }
  }

  /* ───────── Zeit-Helfer ───────── */
  const parseDay = (d) => new Date(String(d).slice(0, 10) + "T12:00:00");
  const fmtDay = (d) => parseDay(d).toLocaleDateString("de-DE", { day: "numeric", month: "long" });
  const fmtShort = (d) => parseDay(d).toLocaleDateString("de-DE", { weekday: "short", day: "numeric", month: "numeric" });
  function until(iso) {
    const m = Math.max(0, (new Date(iso).getTime() - Date.now()) / 6e4);
    if (m < 60) return `noch ${Math.max(1, Math.round(m))} Min.`;
    const h = Math.floor(m / 60), d = Math.floor(h / 24);
    if (d >= 1) return `noch ${d} ${d === 1 ? "Tag" : "Tage"}${h % 24 ? ` ${h % 24} Std.` : ""}`;
    return `noch ${h} Std.`;
  }
  function nextCrown() { const t = new Date(); t.setHours(20, 0, 0, 0); if (t.getTime() <= Date.now()) t.setDate(t.getDate() + 1); return t; }
  const dayKey = (t) => { const d = new Date(t); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };

  /* ───────── Bewertungs-Serie (nur in diesem Browser) ───────── */
  function streakCount() {
    const days = new Set(store.get("streak", []));
    let n = 0, t = Date.now();
    if (!days.has(dayKey(t))) t -= 864e5;              // heute noch nicht bewertet: Serie von gestern zählt noch
    while (days.has(dayKey(t))) { n++; t -= 864e5; }
    return n;
  }
  function markActivity() {
    const today = dayKey(Date.now()), days = store.get("streak", []);
    if (days.includes(today)) return;
    days.push(today); store.set("streak", days.slice(-60));
    const n = streakCount();
    if (n >= 2) toast(`🔥 ${n} Tage in Folge dabei!${[3, 7, 30].includes(n) ? " Neues Abzeichen!" : ""}`);
  }
  const STREAK_BADGES = [[3, "Stammgast", "3 Tage in Folge bewertet"], [7, "Wochen-Held", "7 Tage in Folge"], [30, "Lach-Legende", "30 Tage in Folge"]];

  /* ───────── Challenge & Hinweise (für Banner) ───────── */
  let challengeLoad = null;
  function loadChallenge(force) {
    if (S.challenges && !force) return Promise.resolve(S.challenges);
    if (!challengeLoad || force) challengeLoad = API.challenges().then((c) => (S.challenges = c)).catch(() => (S.challenges = [])).finally(() => { challengeLoad = null; });
    return challengeLoad;
  }
  const activeChallenge = () => (S.challenges || []).find((c) => c.active) || null;
  async function loadHighlights() {
    if (!AUTH || !LIVE) { S.hl = []; return; }
    try {
      const seen = new Set(store.get("hl_seen", []));
      S.hl = (await API.highlights()).filter((h) => !seen.has(`${h.kind}:${h.joke_id}:${h.value}`));
    } catch (e) { S.hl = []; }
  }
  function hlText(h) {
    if (h.kind === "rank") return h.value === 1 ? "🏆 Dein Witz steht gerade auf Platz 1 von heute!" : `🥈 Dein Witz ist gerade auf Platz ${h.value} von heute!`;
    if (h.kind === "crown") return `👑 Dein Witz wurde zum Witz des Tages gekrönt (${fmtDay(String(h.value).replace(/(\d{4})(\d\d)(\d\d)/, "$1-$2-$3"))})!`;
    return `🎉 Dein Witz hat ${fmt(h.value)} Likes geknackt!`;
  }
  function bannersHtml() {
    const out = [];
    for (const h of (S.hl || []).slice(0, 2)) {
      out.push(`<div class="banner hl"><a href="#/witz/${h.joke_id}">${hlText(h)}</a><button class="x" data-hl-dismiss="${esc(`${h.kind}:${h.joke_id}:${h.value}`)}" aria-label="Hinweis schließen">×</button></div>`);
    }
    const c = activeChallenge();
    if (c && !store.get("challenge_hidden_" + c.id, false)) out.push(`<a class="banner ch" href="#/challenge"><span class="ch-k">Challenge der Woche</span><strong>${esc(c.title)}</strong><span class="ch-m">${until(c.ends_at)} · Mitmachen →</span></a>`);
    return out.join("");
  }
  function drawListBanners() { const el = $("#listBanners"); if (el) el.innerHTML = bannersHtml(); }

  /* ───────── Kleine Karte (Highlights, Archiv) ───────── */
  function miniHtml(j, label, extra) {
    return `<a class="mini" href="#/witz/${j.id}"><span class="mini-k">${label}</span><span class="mini-t">${esc(j.text)}</span><span class="mini-m">@${esc(j.author)}${extra ? " · " + extra : ""}</span></a>`;
  }

  /* ───────── Highlights ───────── */
  async function renderHighlights(token) {
    $("#main").innerHTML = '<p class="loading">Lade Highlights …</p>';
    const safe = (p, d) => p.catch(() => d);
    const [daily, authors, champs, lol, sigh, dead] = await Promise.all([
      safe(API.daily(7), []), safe(API.authors("week"), []), safe(API.duelRanking(3), []),
      safe(API.reactionTop("lol", 1), []), safe(API.reactionTop("sigh", 1), []), safe(API.reactionTop("dead", 1), []), loadChallenge(),
    ]);
    if (stale(token)) return;
    S.daily = daily;
    const top = daily[0], c = activeChallenge(), past = (S.challenges || []).filter((x) => !x.active && x.winner_joke);
    const n = streakCount(), wb = authors[0];
    const reactRows = [[lol[0], "😂 Lacher der Woche"], [sigh[0], "🙄 Größter Seufzer der Woche"], [dead[0], "💀 Schwärzester der Woche"]].filter(([j]) => j);
    $("#main").innerHTML = `<div class="view">
      <h1>Highlights</h1>
      <section class="crown">
        <div class="crown-k">👑 Witz des Tages${top ? " · " + fmtDay(top.day) : ""}</div>
        ${top ? `<p class="crown-t">${esc(top.text)}</p>
          <div class="crown-m">${authorLink(top.author)} · ${fmt(top.up)} Likes</div>
          <div class="row"><a class="btn" href="#/witz/${top.id}">Als Story teilen</a></div>`
        : `<p class="crown-t small">Noch kein Witz gekrönt. Bewerte fleißig mit!</p>`}
        <p class="crown-n">Nächste Krönung: ${nextCrown().toLocaleDateString("de-DE", { weekday: "long" })}, 20:00 Uhr (${until(nextCrown().toISOString())})</p>
      </section>
      ${daily.length > 1 ? `<section class="hl-sec"><h2>Die letzten Tage</h2><div class="minis">${daily.slice(1).map((d) => miniHtml(d, "👑 " + fmtShort(d.day))).join("")}</div></section>` : ""}
      ${c ? `<a class="banner ch" href="#/challenge"><span class="ch-k">Challenge der Woche</span><strong>${esc(c.title)}</strong><span class="ch-m">${c.entries} ${c.entries === 1 ? "Beitrag" : "Beiträge"} · ${until(c.ends_at)} · Mitmachen →</span></a>` : ""}
      <section class="hl-sec"><h2>Witzbold der Woche</h2>
        ${wb ? `<a class="mini" href="#/u/${encodeURIComponent(wb.username)}"><span class="mini-k">🃏 Meiste Lacher in 7 Tagen</span><span class="mini-t">@${esc(wb.username)}</span><span class="mini-m">${wb.jokes} ${wb.jokes === 1 ? "Witz" : "Witze"} · ${fmt(wb.up_count)} Likes · Score ${(wb.score * 100).toFixed(1)}</span></a>
          <a class="link more-link" href="#/autoren">Alle Autoren ansehen</a>`
        : `<p class="muted small on-y">Noch kein Witzbold diese Woche. Poste Witze und sammle Lacher!</p>`}
      </section>
      ${reactRows.length ? `<section class="hl-sec"><h2>Reaktionen der Woche</h2><div class="minis">${reactRows.map(([j, l]) => miniHtml(j, l, `${fmt(j.n)}×`)).join("")}</div></section>` : ""}
      ${champs.length ? `<section class="hl-sec"><h2>Duell-Champions</h2><div class="minis">${champs.map((j, i) => miniHtml(j, `⚔️ Platz ${i + 1}`, `${j.duels} Duelle`)).join("")}</div><a class="link more-link" href="#/duell">Selbst Duelle entscheiden</a></section>` : ""}
      ${past.length ? `<section class="hl-sec"><h2>Challenge-Sieger</h2><div class="minis">${past.map((x) => `<a class="mini" href="#/witz/${x.winner_joke}"><span class="mini-k">🏅 ${esc(x.title)}</span><span class="mini-t">@${esc(x.winner_name || "")}</span></a>`).join("")}</div></section>` : ""}
      <section class="hl-sec"><h2>Deine Serie</h2>
        <div class="streak"><span class="streak-n">🔥 ${n}</span><span>${n === 1 ? "Tag" : "Tage"} in Folge bewertet</span></div>
        <div class="badges">${STREAK_BADGES.map(([d, name, desc]) => `<span class="bdg${n >= d ? " on" : ""}" title="${desc}">${name}<small>${desc}</small></span>`).join("")}</div>
        ${installHtml()}
      </section>
    </div>`;
  }

  /* ───────── Duell ───────── */
  const D = { pair: [], done: 0, busy: false };
  async function renderDuel(token) {
    if (D.pair.length < 2) {
      $("#main").innerHTML = '<p class="loading">Lade Duell …</p>';
      D.pair = await API.duel();
      if (stale(token)) return;
    }
    drawDuel();
  }
  function drawDuel() {
    const [a, b] = D.pair;
    const intro = `<div><h1>Witze-Duell</h1><p class="muted">Welcher ist lustiger? Tipp auf deinen Favoriten.</p></div>`;
    if (!a || !b) {
      $("#main").innerHTML = `<div class="view">${intro}<div class="swipe-empty"><h2>Keine Duelle mehr</h2><p class="muted">Du hast alle Paarungen entschieden. Schau später wieder vorbei!</p><div class="row center"><a class="btn ghost" href="#/highlights">Highlights</a></div></div></div>`;
      return;
    }
    const card = (j, k) => `<button class="duel-card" data-duel="${j.id}" data-other="${(k ? a : b).id}"><span class="tag">${CATS[j.cat] || ""}</span><span class="duel-t">${esc(j.text)}</span><span class="duel-pick">Der ist besser</span></button>`;
    $("#main").innerHTML = `<div class="view">${intro}
      <div class="duel-grid">${card(a, 0)}<div class="vs" aria-hidden="true">VS</div>${card(b, 1)}</div>
      <div class="row center"><button class="btn ghost" data-duel-skip>Beide gleich – nächstes Duell</button></div>
      <p class="swipe-hint">${D.done ? D.done + " entschieden · " : ""}Tastatur: 1 = oben · 2 = unten · ↓ überspringen</p>
    </div>`;
  }
  async function duelPick(winner, loser) {
    if (D.busy) return;
    D.busy = true;
    if (winner) {
      document.querySelectorAll(".duel-card").forEach((el) => el.classList.add(Number(el.dataset.duel) === winner ? "won" : "lost"));
      D.done++;
      API.duelVote(winner, loser).then(markActivity).catch((e) => toast(errorText(e)));
    }
    const next = API.duel().catch(() => []);
    await new Promise((r) => setTimeout(r, winner ? 420 : 0));
    D.pair = await next; D.busy = false;
    if (route().view === "duel") drawDuel();
  }

  /* ───────── Autoren ───────── */
  async function renderAuthors(token) {
    $("#main").innerHTML = '<p class="loading">Lade Autoren …</p>';
    const rows = await API.authors(S.authorRange);
    if (stale(token)) return;
    $("#main").innerHTML = `<div class="view">
      <div><h1>Witzbolde</h1><p class="muted">Die Autoren mit den meisten Lachern.</p></div>
      <div class="tabs" role="tablist">
        <button role="tab" data-authrange="week" aria-selected="${S.authorRange === "week"}">Diese Woche</button>
        <button role="tab" data-authrange="all" aria-selected="${S.authorRange === "all"}">Alltime</button>
      </div>
      ${rows.length ? `<ol class="authors">${rows.map((a, i) => `<li><a href="#/u/${encodeURIComponent(a.username)}">
          <span class="a-rank">${i + 1}</span>
          <span class="a-name">@${esc(a.username)}${i === 0 ? ` <span class="pill">${S.authorRange === "week" ? "Witzbold der Woche" : "Allzeit-Bester"}</span>` : ""}</span>
          <span class="a-meta">${a.jokes} ${a.jokes === 1 ? "Witz" : "Witze"} · ${fmt(a.up_count)} Likes · Score ${(a.score * 100).toFixed(1)}</span></a></li>`).join("")}</ol>`
        : `<p class="empty">${S.authorRange === "week" ? "Diese Woche hat noch kein Autor genug Stimmen (mind. 5)." : "Noch hat kein Autor 20 Stimmen gesammelt."} Poste Witze und teil sie!</p>`}
      <section class="how"><h2>So wird gezählt</h2><p>Alle Likes und Dislikes der Witze eines Autors zusammen, bewertet mit dem Wilson-Score. Wer viele mittelmäßige Witze postet, landet deshalb nicht automatisch vorn. Mindestens 5 Stimmen pro Woche bzw. 20 insgesamt. Witze der Lachwerk-Redaktion zählen nicht mit.</p></section>
    </div>`;
  }

  /* ───────── Profil ───────── */
  const BADGES = [
    ["Erster Witz", "Den ersten Witz gepostet", (p) => p.jokes >= 1],
    ["Fleißig", "10 Witze gepostet", (p) => p.jokes >= 10],
    ["Auf dem Podest", "Gerade unter den Top 3 von heute", (p) => p.best_rank && p.best_rank <= 3],
    ["Witz des Tages", "Einmal zum Witz des Tages gekrönt", (p) => p.crowns >= 1],
    ["Dauerbrenner", "3× Witz des Tages", (p) => p.crowns >= 3],
    ["Publikumsliebling", "Ein Witz mit 100 Likes", (p) => p.top_up >= 100],
    ["Lachmaschine", "500 Likes insgesamt", (p) => p.up_count >= 500],
    ["Challenge-Sieger", "Eine Wochen-Challenge gewonnen", (p) => p.challenge_wins >= 1],
  ];
  async function renderProfile(token, name) {
    $("#main").innerHTML = '<p class="loading">Lade Profil …</p>';
    if (name === "Lachwerk") {
      $("#main").innerHTML = `<div class="view"><div class="profile-head"><div class="avatar" aria-hidden="true">L</div><div><h1>@Lachwerk</h1><p class="muted">Die Redaktion. Wir sorgen für Nachschub, bis die Community übernimmt.</p></div></div><a class="btn ghost" href="#/autoren">Zu den Autoren</a></div>`;
      return;
    }
    const [p, jokes] = await Promise.all([API.profile(name), API.profileJokes(name)]);
    if (stale(token)) return;
    if (!p) { $("#main").innerHTML = `<div class="view"><p class="empty">Dieses Profil gibt es nicht.</p><a class="btn ghost" href="#/autoren">Zu den Autoren</a></div>`; return; }
    const isMe = AUTH && AUTH.username && AUTH.username.toLowerCase() === p.username.toLowerCase();
    const n = p.up_count + p.down_count;
    S.rows = jokes;
    $("#main").innerHTML = `<div class="view">
      <div class="profile-head"><div class="avatar" aria-hidden="true">${esc(p.username.slice(0, 1).toUpperCase())}</div>
        <div><h1>@${esc(p.username)}</h1><p class="muted">${p.member_since ? "Dabei seit " + new Date(p.member_since).toLocaleDateString("de-DE", { month: "long", year: "numeric" }) : "Witzbold"}${isMe ? " · Das bist du" : ""}</p></div></div>
      <div class="stats">
        <div><b>${fmt(p.jokes)}</b><span>Witze</span></div>
        <div><b>${fmt(p.up_count)}</b><span>Likes</span></div>
        <div><b>${n ? Math.round((p.up_count / n) * 100) + " %" : "–"}</b><span>Lacher-Quote</span></div>
        <div><b>${fmt(p.crowns)}</b><span>× Witz des Tages</span></div>
      </div>
      <section class="hl-sec"><h2>Abzeichen</h2><div class="badges">${BADGES.map(([b, d, ok]) => `<span class="bdg${ok(p) ? " on" : ""}" title="${d}">${b}<small>${d}</small></span>`).join("")}</div></section>
      <div class="meta-row"><span>Beste Witze von @${esc(p.username)}</span><span>${jokes.length} ${jokes.length === 1 ? "Witz" : "Witze"}</span></div>
      ${jokes.length ? `<ol class="list">${jokes.map((j, i) => cardHtml(j, i + 1, "")).join("")}</ol>` : `<p class="empty">${isMe ? "Du hast noch keinen Witz gepostet. Leg los!" : "Noch keine Witze."}</p>`}
      ${isMe ? `<div class="row center"><button class="btn accent" data-post>Neuen Witz posten</button></div>` : ""}
    </div>`;
    loadReactions(jokes);
  }

  /* ───────── Challenge ───────── */
  async function renderChallenge(token) {
    $("#main").innerHTML = '<p class="loading">Lade Challenge …</p>';
    await loadChallenge(true);
    const c = activeChallenge();
    const rows = c ? await API.challengeRanking(c.id) : [];
    if (stale(token)) return;
    S.rows = rows;
    const past = (S.challenges || []).filter((x) => !x.active);
    $("#main").innerHTML = `<div class="view">
      ${c ? `<section class="crown ch-hero"><div class="crown-k">Challenge der Woche · ${until(c.ends_at)}</div>
          <h1>${esc(c.title)}</h1>${c.description ? `<p>${esc(c.description)}</p>` : ""}
          <p class="crown-n">Endet ${new Date(c.ends_at).toLocaleString("de-DE", { weekday: "long", hour: "2-digit", minute: "2-digit" })} Uhr · ${c.entries} ${c.entries === 1 ? "Beitrag" : "Beiträge"}</p>
          <div class="row"><button class="btn" data-challenge-join>Witz einreichen</button></div></section>
        <div class="meta-row"><span>Rangliste der Challenge</span><span>${rows.length} ${rows.length === 1 ? "Witz" : "Witze"}</span></div>
        ${rows.length ? `<ol class="list">${rows.map((j, i) => cardHtml(j, i + 1, i === 0 ? "Vorn" : "")).join("")}</ol>` : `<p class="empty">Noch keine Beiträge. Reich den ersten ein!</p>`}`
      : `<p class="empty">Gerade läuft keine Challenge. Die nächste kommt bestimmt!</p>`}
      ${past.length ? `<section class="hl-sec"><h2>Frühere Challenges</h2><div class="minis">${past.map((x) => x.winner_joke
        ? `<a class="mini" href="#/witz/${x.winner_joke}"><span class="mini-k">🏅 ${esc(x.title)}</span><span class="mini-t">Gewonnen von @${esc(x.winner_name || "")}</span><span class="mini-m">${x.entries} Beiträge</span></a>`
        : `<div class="mini"><span class="mini-k">${esc(x.title)}</span><span class="mini-t">Ohne Sieger</span></div>`).join("")}</div></section>` : ""}
    </div>`;
    loadReactions(rows);
  }

  /* ───────── App installieren (PWA) ───────── */
  let installEvt = null;
  window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); installEvt = e; });
  const isStandalone = () => (window.matchMedia && matchMedia("(display-mode: standalone)").matches) || navigator.standalone === true;
  function installHtml() {
    if (isStandalone()) return "";
    const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
    return `<div class="install"><strong>Lachwerk als App</strong><span>${ios ? "In Safari auf „Teilen“ und dann „Zum Home-Bildschirm“ tippen." : "Mit einem Tipp auf deinen Startbildschirm, ganz ohne App-Store."}</span>${ios ? "" : `<button class="btn ghost" data-install>App installieren</button>`}</div>`;
  }
  async function doInstall() {
    if (installEvt) { installEvt.prompt(); try { await installEvt.userChoice; } catch (e) { /* egal */ } installEvt = null; return; }
    toast("Öffne das Browser-Menü (⋮) und wähle „App installieren“ bzw. „Zum Startbildschirm“.");
  }

  /* ───────── Moderation ───────── */
  async function renderAdmin(token) {
    if (!S.adminKey) {
      $("#main").innerHTML = `<div class="view"><h1>Moderation</h1>
        <form class="form" id="adminForm">
          <label>Admin-Schlüssel<input type="password" id="adminKey" autocomplete="current-password"></label>
          ${LIVE ? "" : `<p class="muted small">Demo-Modus: Der Schlüssel ist <code>${DEMO_ADMIN_KEY}</code>.</p>`}
          <p class="err" id="adminErr"></p>
          <div><button class="btn">Anmelden</button></div>
        </form></div>`;
      return;
    }
    $("#main").innerHTML = '<p class="loading">Lade Moderation …</p>';
    const v = S.adminView;
    let rows, extra;
    try {
      if (v === "stats") extra = await Promise.all([API.adminTotals(S.adminKey), API.adminStats(S.adminKey, 14), API.adminCatStats(S.adminKey)]);
      else if (v === "vorrat") extra = await Promise.all([API.adminTotals(S.adminKey), API.adminCatStats(S.adminKey)]);
      else if (v === "challenge") extra = await loadChallenge(true);
      else rows = await API.adminList(S.adminKey, v);
    }
    catch (e) { if (e.code === "not_admin") { S.adminKey = null; session.set("admin", null); return render(); } throw e; }
    if (stale(token)) return;
    const label = { visible: "Sichtbar", hidden: "Ausgeblendet", removed: "Entfernt" };
    const head = `<div class="row" style="justify-content:space-between;align-items:center"><h1>Moderation</h1><button class="link" data-admin-logout>Abmelden</button></div>
      <div class="tabs admin-tabs" role="tablist">
        ${[["gemeldet", "Zu prüfen"], ["neu", "Neueste"], ["stats", "Statistik"], ["vorrat", "Vorrat"], ["challenge", "Challenge"]].map(([k, l]) => `<button role="tab" data-adminview="${k}" aria-selected="${v === k}">${l}</button>`).join("")}
      </div>`;
    if (v === "stats") { $("#main").innerHTML = `<div class="view">${head}${adminStatsHtml(...extra)}</div>`; return; }
    if (v === "vorrat") { $("#main").innerHTML = `<div class="view">${head}${adminQueueHtml(...extra)}</div>`; return; }
    if (v === "challenge") { $("#main").innerHTML = `<div class="view">${head}${adminChallengeHtml(extra)}</div>`; return; }
    $("#main").innerHTML = `<div class="view">
      ${head}
      ${rows.length ? `<ul class="mod-list">${rows.map((j) => `<li class="mod-item st-${j.status}">
        <div class="mod-head"><span class="pill st-${j.status}">${label[j.status] || j.status}</span>
          ${j.reports ? `<span class="pill reports">${j.reports} ${j.reports === 1 ? "Meldung" : "Meldungen"}</span>` : ""}
          <span class="muted small">${CATS[j.cat] || ""} · @${esc(j.author)} · ${ago(j.created)} · ${fmt(j.up + j.down)} Stimmen</span></div>
        <p class="txt">${esc(j.text)}</p>
        <div class="row">
          ${j.status === "hidden" || j.reports > 0 ? `<button class="btn ghost" data-approve="${j.id}">${j.status === "hidden" ? "Freigeben" : "Meldungen verwerfen"}</button>` : ""}
          <button class="btn danger" data-remove="${j.id}">Entfernen</button>
        </div></li>`).join("")}</ul>`
        : `<p class="empty">${S.adminView === "neu" ? "Noch keine Witze." : "Keine gemeldeten Witze. Alles ruhig."}</p>`}
      <p class="muted small">Ein freigegebener Witz wird erst nach 10 neuen Meldungen wieder automatisch ausgeblendet.</p>
    </div>`;
  }

  function adminStatsHtml(t, days, cats) {
    const max = Math.max(1, ...days.map((d) => d.votes + d.reactions + d.duels));
    const tile = (n, l) => `<div><b>${n}</b><span>${l}</span></div>`;
    return `<div class="stats">${tile(fmt(t.jokes), "Witze sichtbar")}${tile(fmt(t.user_jokes), "von Nutzern")}${tile(fmt(t.users), "Konten")}${tile(fmt(t.votes), "Stimmen gesamt")}${tile(fmt(t.devices), "Geräte haben abgestimmt")}${tile(fmt(t.queued), "im Vorrat")}</div>
      <section class="panel"><h2>Letzte 14 Tage</h2>
        <table class="tbl"><thead><tr><th>Tag</th><th>Aktivität</th><th>Besucher</th><th>Stimmen</th><th>Reakt.</th><th>Duelle</th><th>Witze</th><th>Konten</th></tr></thead><tbody>
        ${days.slice().reverse().map((d) => `<tr><td>${fmtShort(d.day)}</td><td class="bar"><i style="width:${Math.round(((d.votes + d.reactions + d.duels) / max) * 100)}%"></i></td><td>${d.voters}</td><td>${d.votes}</td><td>${d.reactions}</td><td>${d.duels}</td><td>${d.new_jokes}</td><td>${d.signups}</td></tr>`).join("")}
        </tbody></table>
        <p class="muted small">Besucher = verschiedene Geräte, die an dem Tag abgestimmt, reagiert oder ein Duell entschieden haben. Reine Leser werden nicht gezählt (kein Tracking).</p></section>
      <section class="panel"><h2>Kategorien</h2>
        <table class="tbl"><thead><tr><th>Kategorie</th><th>Witze</th><th>im Vorrat</th><th>Stimmen 7 Tage</th></tr></thead><tbody>
        ${cats.map((c) => `<tr><td>${esc(c.name)}</td><td>${c.jokes}</td><td>${c.queued}</td><td>${c.votes_week}</td></tr>`).join("")}</tbody></table></section>`;
  }
  function adminQueueHtml(t, cats) {
    return `<section class="panel"><h2>Witz-Vorrat</h2>
        <p class="muted small">${t.queued ? `${fmt(t.queued)} Witze sind eingeplant und erscheinen nach und nach, der letzte am ${new Date(t.queue_until).toLocaleDateString("de-DE", { day: "numeric", month: "long" })}.` : "Der Vorrat ist leer. „Heute“ füllt sich nur noch durch Beiträge der Nutzer."}</p>
        <div class="chips static">${cats.filter((c) => c.queued).map((c) => `<span class="chip">${esc(c.name)}: ${c.queued}</span>`).join("")}</div></section>
      <form class="panel form" id="bulkForm">
        <h2>Witze nachlegen</h2>
        <label>Kategorie<select id="bulkCat">${Object.entries(CATS).map(([k, l]) => `<option value="${k}">${l}</option>`).join("")}</select></label>
        <label>Witze (durch eine Leerzeile getrennt)<textarea id="bulkText" rows="10" placeholder="Erster Witz …\nPointe in der zweiten Zeile.\n\nZweiter Witz …"></textarea></label>
        <label>Wie viele pro Tag?<input type="number" id="bulkPer" min="1" max="48" value="3" inputmode="numeric"></label>
        <p class="muted small">Die Witze erscheinen im Anschluss an den schon geplanten Vorrat, als Autor steht „Lachwerk“. Doppelte werden übersprungen.</p>
        <p class="err" id="bulkErr"></p>
        <div><button class="btn">Einplanen</button></div>
      </form>`;
  }
  const toLocalInput = (iso) => { const d = new Date(iso); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };
  function adminChallengeHtml(list) {
    const e = S.editChallenge || {};
    const start = e.starts_at ? toLocalInput(e.starts_at) : toLocalInput(new Date().toISOString());
    const end0 = new Date(); end0.setDate(end0.getDate() + 7); end0.setHours(20, 0, 0, 0);
    const end = e.ends_at ? toLocalInput(e.ends_at) : toLocalInput(end0.toISOString());
    return `<form class="panel form" id="challengeForm">
        <h2>${e.id ? "Challenge bearbeiten" : "Neue Challenge"}</h2>
        <label>Thema<input type="text" id="chTitle" maxlength="80" value="${esc(e.title || "")}" placeholder="z. B. Witze über Kollegen"></label>
        <label>Beschreibung<textarea id="chDesc" maxlength="300" rows="3">${esc(e.description || "")}</textarea></label>
        <label>Start<input type="datetime-local" id="chStart" value="${start}"></label>
        <label>Ende<input type="datetime-local" id="chEnd" value="${end}"></label>
        <p class="err" id="chErr"></p>
        <div class="row">${e.id ? '<button type="button" class="btn ghost" data-ch-new>Abbrechen</button>' : ""}<button class="btn">Speichern</button></div>
      </form>
      <section class="panel"><h2>Bisherige Challenges</h2>
        ${list.length ? `<ul class="mod-list">${list.map((c) => `<li class="mod-item"><div class="mod-head"><span class="pill${c.active ? " st-visible" : ""}">${c.active ? "Läuft" : "Beendet"}</span><strong>${esc(c.title)}</strong></div>
          <span class="muted small">${new Date(c.starts_at).toLocaleDateString("de-DE")} – ${new Date(c.ends_at).toLocaleString("de-DE", { day: "numeric", month: "numeric", hour: "2-digit", minute: "2-digit" })} · ${c.entries} Beiträge${c.winner_name ? " · Sieger @" + esc(c.winner_name) : ""}</span>
          <div><button class="btn ghost" data-ch-edit="${c.id}">Bearbeiten</button></div></li>`).join("")}</ul>` : '<p class="muted small">Noch keine.</p>'}
        <p class="muted small">Geplante Challenges, die noch nicht begonnen haben, erscheinen hier erst ab ihrem Start.</p></section>`;
  }

  /* ───────── Posten ───────── */
  let simTimer = null, simSeq = 0;
  function showDup(d) {
    const box = $("#dupBox");
    box.hidden = !d;
    $("#postSubmit").disabled = !!d;
    if (d) box.innerHTML = `<div class="dup"><strong>Diesen Witz gibt es schon${d.match ? ` (${Math.round(d.match * 100)} % ähnlich)` : ""}.</strong>
      ${d.text ? `<q>${esc(d.text)}</q>` : ""}<div><a class="btn ghost" href="#/witz/${d.id}" data-close>Zum Original</a></div></div>`;
  }
  function checkSimilar() {
    clearTimeout(simTimer);
    const t = $("#postText").value.trim();
    if (t.length < 10) { showDup(null); return; }
    const seq = ++simSeq;
    simTimer = setTimeout(() => { API.similar(t).then((d) => { if (seq === simSeq) showDup(d); }).catch(() => {}); }, 350);
  }
  function openSheet(id) { $(id).hidden = false; const f = $(id).querySelector("textarea") || $(id).querySelector("input"); if (f) setTimeout(() => f.focus(), 30); }
  function closeSheets() { document.querySelectorAll(".scrim").forEach((s) => (s.hidden = true)); }
  function toast(m) { const t = $("#toast"); t.textContent = m; t.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => (t.hidden = true), 2600); }

  /* ───────── Ereignisse ───────── */
  let reportId = null;
  document.addEventListener("click", (e) => {
    if (e.target.classList && e.target.classList.contains("scrim")) { closeSheets(); return; }
    const t = e.target.closest("button, a"); if (!t) return;
    const d = t.dataset;
    if ("close" in d) { closeSheets(); if (t.tagName === "BUTTON") return; }
    if (d.range) { S.range = d.range; S.shown = PAGE; S.rows = []; document.querySelectorAll("[data-range]").forEach((b) => b.setAttribute("aria-selected", b === t)); render(); return; }
    if (d.cat !== undefined && t.classList.contains("chip")) { S.cat = d.cat || null; S.shown = PAGE; S.rows = []; renderChips(); render(); return; }
    if (d.morecat) { S.cat = d.morecat; S.range = "all"; S.rows = []; document.querySelectorAll("[data-range]").forEach((b) => b.setAttribute("aria-selected", b.dataset.range === "all")); renderChips(); location.hash = "#/"; return; }
    if ("more" in d) { S.shown += PAGE; render(); return; }
    if ("retry" in d) { render(); return; }
    if (d.vote) { vote(Number(d.id), Number(d.vote)); return; }
    if (d.react) { const id = Number(d.id); react(id, d.react, findRow(id) || { id, own: false }); return; }
    if (d.duel) { duelPick(Number(d.duel), Number(d.other)); return; }
    if ("duelSkip" in d) { duelPick(null, null); return; }
    if (d.authrange) { S.authorRange = d.authrange; render(); return; }
    if (d.hlDismiss) { store.set("hl_seen", [...store.get("hl_seen", []), d.hlDismiss].slice(-200)); S.hl = S.hl.filter((h) => `${h.kind}:${h.joke_id}:${h.value}` !== d.hlDismiss); drawListBanners(); return; }
    if ("challengeJoin" in d) { openPost(true); return; }
    if ("install" in d) { doInstall(); return; }
    if (d.chEdit) { S.editChallenge = (S.challenges || []).find((c) => c.id === Number(d.chEdit)) || null; render(); return; }
    if ("chNew" in d) { S.editChallenge = null; render(); return; }
    if (d.swipe !== undefined) { decide(Number(d.swipe)); return; }
    if (d.report) { reportId = Number(d.report); openSheet("#reportSheet"); return; }
    if ("post" in d) { openPost(false); return; }
    if ("shareImage" in d) { shareImage(); return; }
    if ("shareLink" in d) { shareLink(); return; }
    if (d.adminview) { S.adminView = d.adminview; render(); return; }
    if ("adminLogout" in d) { S.adminKey = null; session.set("admin", null); location.hash = "#/"; return; }
    if (d.approve || d.remove) {
      const id = Number(d.approve || d.remove);
      t.disabled = true;
      API.adminSet(S.adminKey, id, d.approve ? "visible" : "removed")
        .then(() => { toast(d.approve ? "Freigegeben." : "Entfernt."); render(); })
        .catch((err) => { t.disabled = false; toast(errorText(err)); });
      return;
    }
  });
  $("#reportConfirm").addEventListener("click", async () => {
    const id = reportId; closeSheets();
    S.hiddenForMe.add(id); store.set("hidden", [...S.hiddenForMe]);
    try { await API.report(id); toast("Gemeldet. Danke!"); } catch (e) { toast(errorText(e)); }
    S.rows = S.rows.filter((j) => j.id !== id);
    if (route().view === "detail") location.hash = "#/"; else render();
  });
  /* ───────── Anmelden, Registrieren, Passwort ───────── */
  let authMode = "login", afterLogin = null;
  function openAuth(mode, reason, next) {
    authMode = mode; afterLogin = next || null;
    $("#authReason").textContent = reason || "Lesen, Liken und Bewerten geht auch ohne Konto. Zum Posten brauchst du eins.";
    $("#authErr").textContent = ""; $("#authOk").hidden = true; $("#authFields").hidden = false;
    drawAuthMode(); openSheet("#authSheet");
  }
  function drawAuthMode() {
    const titles = { login: "Anmelden", signup: "Registrieren", forgot: "Passwort vergessen" };
    $("#authTitle").textContent = titles[authMode];
    $("#authTabs").hidden = authMode === "forgot";
    document.querySelectorAll("[data-authmode]").forEach((b) => b.setAttribute("aria-selected", b.dataset.authmode === authMode));
    $("#authNameRow").hidden = authMode !== "signup";
    $("#authConsentRow").hidden = authMode !== "signup";
    $("#authPwRow").hidden = authMode === "forgot";
    $("#authPw").autocomplete = authMode === "signup" ? "new-password" : "current-password";
    $("#forgotBtn").hidden = authMode !== "login";
    $("#authSubmit").textContent = { login: "Anmelden", signup: "Konto erstellen", forgot: "Link schicken" }[authMode];
    $("#authDemo").hidden = LIVE;
  }
  $("#who").addEventListener("click", () => {
    if (!AUTH) { openAuth("login"); return; }
    $("#accountInfo").textContent = `Angemeldet als @${AUTH.username || "…"}${AUTH.email ? " (" + AUTH.email + ")" : ""}.`;
    $("#accountPw").hidden = !LIVE;
    $("#accountProfile").href = "#/u/" + encodeURIComponent(AUTH.username || "");
    openSheet("#accountSheet");
  });
  $("#authForm").addEventListener("click", (e) => {
    const b = e.target.closest("[data-authmode]");
    if (b) { authMode = b.dataset.authmode; $("#authErr").textContent = ""; drawAuthMode(); }
  });
  $("#forgotBtn").addEventListener("click", () => { authMode = "forgot"; $("#authErr").textContent = ""; drawAuthMode(); });
  $("#authForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const name = $("#authName").value.trim(), email = $("#authEmail").value.trim(), pw = $("#authPw").value, err = $("#authErr");
    err.textContent = "";
    if (authMode === "signup" && !USERNAME_RE.test(name)) { err.textContent = ERRORS.invalid_username; return; }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { err.textContent = ERRORS.invalid_email; return; }
    if (authMode !== "forgot" && pw.length < (authMode === "signup" ? 8 : 1)) { err.textContent = ERRORS.password_short; return; }
    if (authMode === "signup" && !$("#authConsent").checked) { err.textContent = ERRORS.consent_missing; return; }
    const btn = $("#authSubmit"), label = btn.textContent; btn.disabled = true; btn.textContent = "Einen Moment …";
    try {
      if (authMode === "login") {
        await AUTH_API.signIn(email, pw);
        closeSheets(); toast(`Hallo @${AUTH.username}!`); render();
        if (afterLogin === "post" || afterLogin === "challenge") openPost(afterLogin === "challenge");
      } else if (authMode === "signup") {
        const r = await AUTH_API.signUp(name, email, pw);
        if (r.confirmed) { closeSheets(); toast(`Willkommen, @${AUTH.username}!`); render(); if (afterLogin === "post" || afterLogin === "challenge") openPost(afterLogin === "challenge"); }
        else { $("#authFields").hidden = true; $("#authOk").hidden = false; $("#authOk").textContent = `Fast geschafft: Wir haben dir eine E-Mail an ${email} geschickt. Klick auf den Link darin, dann bist du angemeldet. Schau auch im Spam-Ordner nach.`; }
      } else {
        await AUTH_API.recover(email);
        $("#authFields").hidden = true; $("#authOk").hidden = false;
        $("#authOk").textContent = LIVE ? `Falls es ein Konto mit ${email} gibt, ist jetzt eine E-Mail mit einem Link zum Zurücksetzen unterwegs.` : "Im Demo-Modus gibt es keine Passwörter. Melde dich einfach mit deiner E-Mail an.";
      }
    } catch (ex) { err.textContent = errorText(ex); }
    finally { btn.disabled = false; btn.textContent = label; }
  });
  $("#logoutBtn").addEventListener("click", async () => { await AUTH_API.signOut(); closeSheets(); toast("Abgemeldet."); render(); });
  $("#accountPw").addEventListener("click", () => { closeSheets(); $("#pwErr").textContent = ""; openSheet("#pwSheet"); });
  $("#pwForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const a = $("#pwNew").value, b = $("#pwNew2").value, err = $("#pwErr");
    if (a.length < 8) { err.textContent = ERRORS.password_short; return; }
    if (a !== b) { err.textContent = ERRORS.password_mismatch; return; }
    try { await AUTH_API.updatePassword(a); $("#pwNew").value = $("#pwNew2").value = ""; closeSheets(); toast("Neues Passwort gespeichert."); }
    catch (ex) { err.textContent = errorText(ex); }
  });
  async function openPost(forChallenge) {
    if (!AUTH) { openAuth("login", "Zum Posten brauchst du ein Konto. Lesen, Liken und Bewerten geht auch ohne.", forChallenge ? "challenge" : "post"); return; }
    $("#postAs").textContent = `Du postest als @${AUTH.username}.`;
    $("#postErr").textContent = "";
    showDup(null); checkSimilar();
    openSheet("#postSheet");
    await loadChallenge();
    const c = activeChallenge();
    $("#postChallengeRow").hidden = !c;
    if (c) { $("#postChallengeName").textContent = c.title; $("#postChallenge").checked = !!forChallenge || route().view === "challenge"; }
  }
  $("#postBtn").addEventListener("click", () => openPost(false));
  $("#postCat").innerHTML = Object.entries(CATS).map(([k, v]) => `<option value="${k}">${v}</option>`).join("");
  $("#postText").addEventListener("input", checkSimilar);
  $("#postForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = $("#postText").value.trim(), cat = $("#postCat").value, err = $("#postErr");
    if (text.length < 10 || text.length > 500) { err.textContent = ERRORS.invalid_body; return; }
    const btn = $("#postSubmit"); btn.disabled = true; btn.textContent = "Wird veröffentlicht …"; err.textContent = "";
    try {
      const c = activeChallenge();
      const id = await API.post(cat, text, c && !$("#postChallengeRow").hidden && $("#postChallenge").checked ? c.id : null);
      S.challenges = null;
      $("#postText").value = ""; closeSheets();
      S.rows = []; S.range = "day"; S.cat = null;
      document.querySelectorAll("[data-range]").forEach((b) => b.setAttribute("aria-selected", b.dataset.range === "day")); renderChips();
      location.hash = "#/witz/" + id;
      toast("Veröffentlicht. Teil ihn, damit er Stimmen bekommt!");
    } catch (ex) {
      if (ex.code === "duplicate") { showDup({ id: ex.duplicateId }); }
      else if (ex.code === "not_logged_in") { setAuth(null); closeSheets(); openAuth("login", ERRORS.not_logged_in, "post"); }
      else err.textContent = errorText(ex);
    } finally { btn.textContent = "Veröffentlichen"; btn.disabled = !$("#dupBox").hidden; }
  });
  document.addEventListener("submit", async (e) => {
    if (e.target.id === "bulkForm") {
      e.preventDefault();
      const bodies = $("#bulkText").value.split(/\n\s*\n/).map((x) => x.trim()).filter(Boolean);
      if (!bodies.length) { $("#bulkErr").textContent = "Bitte mindestens einen Witz eingeben."; return; }
      const btn = e.target.querySelector("button"); btn.disabled = true;
      try { const r = await API.adminBulkAdd(S.adminKey, $("#bulkCat").value, bodies, Number($("#bulkPer").value) || 3); toast(`${r.inserted} eingeplant${r.skipped ? `, ${r.skipped} übersprungen (doppelt oder zu kurz)` : ""}.`); render(); }
      catch (ex) { $("#bulkErr").textContent = errorText(ex); btn.disabled = false; }
      return;
    }
    if (e.target.id === "challengeForm") {
      e.preventDefault();
      const c = { id: S.editChallenge && S.editChallenge.id, title: $("#chTitle").value.trim(), description: $("#chDesc").value.trim(), starts: new Date($("#chStart").value).toISOString(), ends: new Date($("#chEnd").value).toISOString() };
      if (c.title.length < 3) { $("#chErr").textContent = "Das Thema braucht mindestens 3 Zeichen."; return; }
      if (!(new Date(c.ends) > new Date(c.starts))) { $("#chErr").textContent = "Das Ende muss nach dem Start liegen."; return; }
      try { await API.adminSaveChallenge(S.adminKey, c); S.editChallenge = null; S.challenges = null; toast("Challenge gespeichert."); render(); }
      catch (ex) { $("#chErr").textContent = errorText(ex); }
      return;
    }
    if (e.target.id !== "adminForm") return;
    e.preventDefault();
    const key = $("#adminKey").value.trim();
    try {
      if (await API.adminCheck(key)) { S.adminKey = key; session.set("admin", key); render(); }
      else $("#adminErr").textContent = ERRORS.not_admin;
    } catch (ex) { $("#adminErr").textContent = errorText(ex); }
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { closeSheets(); return; }
    if (document.querySelector(".scrim:not([hidden])")) return;
    if (e.target.closest && e.target.closest("input, textarea, select")) return;
    if (route().view === "duel") {
      const cards = document.querySelectorAll(".duel-card");
      if ((e.key === "1" || e.key === "2") && cards.length === 2) { e.preventDefault(); const w = cards[Number(e.key) - 1]; duelPick(Number(w.dataset.duel), Number(w.dataset.other)); }
      else if (e.key === "ArrowDown") { e.preventDefault(); duelPick(null, null); }
      return;
    }
    if (route().view !== "swipe") return;
    if (e.key === "ArrowRight") { e.preventDefault(); decide(1); }
    else if (e.key === "ArrowLeft") { e.preventDefault(); decide(-1); }
    else if (e.key === "ArrowDown") { e.preventDefault(); decide(0); }
  });
  window.addEventListener("hashchange", () => {
    if (LIVE && /access_token=|error_description=/.test(location.hash)) { handleAuthLink(); return; } // Link aus der E-Mail im selben Tab
    window.scrollTo({ top: 0 }); if (route().view === "swipe") { S.queue = []; S.seen = new Set(); S.rated = 0; S.swipeDone = false; } render();
  });

  $("#demoBanner").hidden = LIVE;
  renderChips();
  function handleAuthLink() {
    return (LIVE ? handleAuthRedirect() : Promise.resolve(null)).then((r) => {
      render();
      if (!r) return;
      closeSheets();
      if (r.error) { toast("Der Link ist abgelaufen oder ungültig. Melde dich an oder fordere einen neuen an."); openAuth("login"); }
      else if (r.type === "recovery") { $("#pwErr").textContent = ""; openSheet("#pwSheet"); toast("Lege jetzt ein neues Passwort fest."); }
      else toast(`E-Mail bestätigt. Willkommen, @${AUTH ? AUTH.username : ""}!`);
    }).catch(() => render());
  }
  handleAuthLink();

  // Installierbar machen und offline anzeigen (nur über https oder localhost)
  if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost")) {
    window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
  }
})();
