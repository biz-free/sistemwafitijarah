// ═══════════════════════════════════════════════
//  SERVICE WORKER — Wafi Tijarah Trading PWA
//  Membolehkan apps berfungsi offline
// ═══════════════════════════════════════════════

const CACHE_NAME = 'wafi-tijarah-v32';
const ASSETS = [
  './pengurusan.html',
  './manifest.json',
  './logo.png',
  './icon-192.png',
  './icon-512.png',
];

// Install — cache semua aset
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      console.log('[SW] Caching app shell');
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate — buang cache lama (versi sebelum ini)
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch:
//  - HTML/JS (kod apps) → network dulu, cache sebagai fallback offline sahaja.
//    Ini pastikan kemaskini apps terus terpakai bila online, bukan tersekat cache lama.
//  - Aset statik (gambar/ikon) → cache dulu (jarang berubah, offline-friendly).
self.addEventListener('fetch', e => {
  if (e.request.url.includes('supabase.co')) return; // kena network, jangan cache
  if (e.request.url.includes('unpkg.com') || e.request.url.includes('cdn.jsdelivr.net')) return; // CDN, biar browser urus

  const isDocOrScript = e.request.destination === 'document' || e.request.url.endsWith('.html');

  if (isDocOrScript) {
    e.respondWith(
      fetch(e.request)
        .then(response => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
          }
          return response;
        })
        .catch(() => caches.match(e.request).then(cached => cached || caches.match('./pengurusan.html')))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(response => {
        if (response && response.status === 200 && response.type === 'basic') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
        }
        return response;
      }).catch(() => {});
    })
  );
});

// Background sync untuk data offline
self.addEventListener('sync', e => {
  if (e.tag === 'sync-transaksi') {
    console.log('[SW] Syncing offline transactions...');
    // Implement sync dengan Supabase di sini
  }
});

// Notifikasi Tolak (Web Push) — terima mesej drpd server (edge function
// notifikasi-invois-lewat-cron), papar sbg notifikasi peranti.
self.addEventListener('push', e => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch { data = { title: 'Wafi Tijarah Trading', body: e.data ? e.data.text() : '' }; }
  const title = data.title || 'Wafi Tijarah Trading';
  e.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || '',
      icon: './icon-192.png',
      badge: './icon-192.png',
      data: { url: data.url || './pengurusan.html' },
    })
  );
});

// Tekan notifikasi — fokus tab sedia ada jika ada, kalau tiada buka tab baharu.
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data?.url || './pengurusan.html';
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) { if ('focus' in c) return c.focus(); }
      return self.clients.openWindow(url);
    })
  );
});
