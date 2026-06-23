/**
 * Panic: Arena — Service Worker
 *
 * Caching strategy:
 *   - NETWORK-FIRST for realtime traffic (Firebase Realtime DB, Cloud
 *     Functions, auth). The game must never serve stale game state from cache.
 *   - CACHE-FIRST for the static app shell + Godot assets (.wasm, .pck, .js,
 *     fonts, textures, audio) so the game boots offline and loads instantly.
 *
 * Bump CACHE_VERSION on every deploy to invalidate the old shell.
 */

const CACHE_VERSION = "panic-arena-v1";
const APP_SHELL = [
  "./",
  "./index.html",
  "./manifest.json",
  "./index.js",
  "./index.wasm",
  "./index.pck",
  "./index.audio.worklet.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
];

// Hosts whose responses must always come from the network (realtime).
const NETWORK_FIRST_HOSTS = [
  "firebaseio.com",
  "cloudfunctions.net",
  "googleapis.com",
  "firebaseapp.com",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return; // never cache writes

  const url = new URL(request.url);
  const isRealtime = NETWORK_FIRST_HOSTS.some((h) => url.hostname.includes(h));

  if (isRealtime) {
    event.respondWith(networkFirst(request));
  } else {
    event.respondWith(cacheFirst(request));
  }
});

async function networkFirst(request) {
  try {
    const fresh = await fetch(request);
    return fresh;
  } catch (err) {
    const cached = await caches.match(request);
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  const fresh = await fetch(request);
  // Cache successful, same-origin static responses for next time.
  if (fresh.ok && new URL(request.url).origin === self.location.origin) {
    const cache = await caches.open(CACHE_VERSION);
    cache.put(request, fresh.clone());
  }
  return fresh;
}
