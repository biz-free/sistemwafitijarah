// ═══════════════════════════════════════════════
//  SERVICE WORKER — Wafi Tijarah Trading PWA
//  Membolehkan apps berfungsi offline
// ═══════════════════════════════════════════════

const CACHE_NAME = 'wafi-tijarah-v2';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
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

// Activate — buang cache lama
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch — serve dari cache dulu (offline-first)
self.addEventListener('fetch', e => {
  // Skip Supabase API calls - kena network
  if (e.request.url.includes('supabase.co')) {
    return;
  }

  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;

      return fetch(e.request).then(response => {
        // Cache resources baru
        if (response && response.status === 200 && response.type === 'basic') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
        }
        return response;
      }).catch(() => {
        // Offline fallback
        if (e.request.destination === 'document') {
          return caches.match('./index.html');
        }
      });
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
