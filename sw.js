// Lachwerk – Service Worker: macht die Seite installierbar und zeigt sie auch ohne Netz an.
// Strategie: immer zuerst das Netz (damit Updates sofort ankommen), bei Funkloch der Zwischenspeicher.
// Anfragen an Supabase (andere Adresse) werden nie zwischengespeichert.
const CACHE = "lachwerk-v10";
const SHELL = ["./", "index.html", "style.css?v=10", "app.js?v=10", "config.js", "startwitze.js", "favicon.svg", "icons/icon-192.png", "manifest.webmanifest"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req).then((hit) => hit || (req.mode === "navigate" ? caches.match("index.html") : Response.error())))
  );
});
