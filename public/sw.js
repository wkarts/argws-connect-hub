/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

const CACHE_VERSION = 'hub-pwa-v1.2.1';
const STATIC_CACHE = `${CACHE_VERSION}-static`;
const RUNTIME_CACHE = `${CACHE_VERSION}-runtime`;
const OFFLINE_URL = '/offline.html';

const PRECACHE_URLS = [
  OFFLINE_URL,
  '/manifest.json',
  '/pwa-icon-192x192.png',
  '/pwa-icon-512x512.png',
  '/pwa-maskable-192x192.png',
  '/pwa-maskable-512x512.png',
  '/favicon-16x16.png',
  '/favicon-32x32.png',
  '/favicon-96x96.png',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches
      .open(STATIC_CACHE)
      .then(cache => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches
      .keys()
      .then(cacheNames =>
        Promise.all(
          cacheNames
            .filter(
              cacheName =>
                cacheName.startsWith('hub-pwa-') &&
                cacheName !== STATIC_CACHE &&
                cacheName !== RUNTIME_CACHE
            )
            .map(cacheName => caches.delete(cacheName))
        )
      )
      .then(() => clients.claim())
  );
});

self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', event => {
  const { request } = event;

  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Never cache authenticated/API traffic. Only navigation fallback and static
  // assets are handled by the PWA worker.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match(OFFLINE_URL))
    );
    return;
  }

  if (!['style', 'script', 'image', 'font'].includes(request.destination)) {
    return;
  }

  event.respondWith(
    caches.match(request).then(cachedResponse => {
      const networkResponse = fetch(request)
        .then(response => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(RUNTIME_CACHE).then(cache => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cachedResponse);

      return cachedResponse || networkResponse;
    })
  );
});

self.addEventListener('push', event => {
  let notification;

  try {
    notification = event.data && event.data.json();
  } catch (error) {
    console.error('Unable to parse push notification payload', error);
    return;
  }

  if (!notification) return;

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      tag: notification.tag,
      body: notification.body,
      icon: notification.icon || '/pwa-icon-192x192.png',
      badge: notification.badge || '/pwa-icon-192x192.png',
      data: {
        url: notification.url || '/',
      },
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const targetUrl = new URL(
    (event.notification.data && event.notification.data.url) || '/',
    self.location.origin
  ).href;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(windowClients => {
      const matchingWindow = windowClients.find(client => client.url === targetUrl);

      if (matchingWindow && 'focus' in matchingWindow) {
        return matchingWindow.focus();
      }

      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }

      return undefined;
    })
  );
});
