// Service worker: deixa o app disponível offline (cache dos arquivos do próprio app).
// Os DADOS ficam no IndexedDB cifrado, não neste cache.
const VERSION = 'lifeos-v1.2.2';
const ASSETS = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'js/app.js', 'js/util.js', 'js/crypto.js', 'js/store.js', 'js/nlp.js', 'js/domain.js', 'js/ui.js', 'js/charts.js',
  'js/backup.js', 'js/notify.js', 'js/sync.js', 'js/config.js',
  'js/views/home.js', 'js/views/agenda.js', 'js/views/assistant.js', 'js/views/finance.js', 'js/views/study.js', 'js/views/studies.js', 'js/views/live.js',
  'js/views/health.js', 'js/views/growth.js', 'js/views/docs.js', 'js/views/reports.js', 'js/views/settings.js',
  'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/icon-180.png', 'icons/icon-maskable-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

// Rede primeiro para os arquivos do app (pega atualizações), cache como reserva offline.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match('index.html')))
  );
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    const w = list.find((c) => 'focus' in c);
    return w ? w.focus() : self.clients.openWindow('./');
  }));
});
