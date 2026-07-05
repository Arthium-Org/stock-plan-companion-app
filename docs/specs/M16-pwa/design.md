# Design: M16 — Progressive Web App (PWA)

## Files to Create/Modify

```
assets/static/
  ├── manifest.json          # Web app manifest
  ├── icons/
  │   ├── icon-192.png       # Android + general
  │   ├── icon-512.png       # Android splash
  │   ├── icon-180.png       # Apple touch icon
  │   └── icon-maskable.png  # Android adaptive
  └── sw.js                  # Service worker

lib/stock_plan_web/components/layouts/
  └── root.html.heex         # Add manifest link + meta tags
  
assets/js/
  └── app.js                 # Register service worker
```

## manifest.json

```json
{
  "name": "Stock Plan Manager",
  "short_name": "StockPlan",
  "description": "RSU, ESPP & Stock Option portfolio management",
  "start_url": "/portfolio",
  "display": "standalone",
  "background_color": "#1d232a",
  "theme_color": "#661ae6",
  "orientation": "any",
  "icons": [
    {
      "src": "/icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "/icons/icon-maskable.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
```

## root.html.heex additions

```html
<head>
  <!-- PWA -->
  <link rel="manifest" href="/manifest.json" />
  <meta name="theme-color" content="#661ae6" />
  
  <!-- iOS -->
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="default" />
  <meta name="apple-mobile-web-app-title" content="StockPlan" />
  <link rel="apple-touch-icon" href="/icons/icon-180.png" />
</head>
```

## Service Worker (sw.js)

```javascript
const CACHE_NAME = 'stockplan-v1';
const SHELL_URLS = [
  '/assets/css/app.css',
  '/assets/js/app.js',
  '/icons/icon-192.png'
];

// Install: cache app shell
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(SHELL_URLS))
  );
});

// Fetch: network-first (LiveView needs live connection)
self.addEventListener('fetch', event => {
  event.respondWith(
    fetch(event.request)
      .catch(() => caches.match(event.request))
  );
});
```

## Service Worker Registration (app.js)

```javascript
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js');
}
```

## Static File Serving

Phoenix serves files from `priv/static/`. Place manifest.json and icons there, or configure endpoint to serve from assets/static.

Alternatively, serve manifest.json via a controller route for dynamic theme support.
