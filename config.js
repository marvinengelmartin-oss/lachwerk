// ─────────────────────────────────────────────────────────────
// Lachwerk – Einstellungen
//
// Leer lassen  → Demo-Modus: läuft sofort, aber Stimmen und Witze
//                bleiben nur im Browser des jeweiligen Besuchers.
// Ausfüllen    → Live-Modus: alle Besucher teilen sich Witze und Stimmen.
//                Werte findest du in Supabase unter
//                Project Settings → API (bzw. "API Keys").
//
// Der "anon"/"publishable" Key ist öffentlich und darf hier stehen.
// Den "service_role"/"secret" Key NIEMALS hier eintragen!
// ─────────────────────────────────────────────────────────────
window.LACHWERK_CONFIG = {
  supabaseUrl: "https://yssqvkhmglwdxvjurxag.supabase.co",
  supabaseAnonKey: "sb_publishable_TI6LLkRXgR6BIR9TykIBPg_KCItfwho",
};
