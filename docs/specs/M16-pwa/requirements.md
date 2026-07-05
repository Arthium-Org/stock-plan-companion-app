# Requirements: M16 — Progressive Web App (PWA)

## Introduction

Make the existing web app installable on iOS and Android as a PWA. Zero new features — same app, installable from browser.

---

## Requirement 1: Web App Manifest

1. Create `manifest.json` with app name, icons, theme color, display mode
2. App name: "Stock Plan Manager"
3. Short name: "StockPlan"
4. Display: `standalone` (full screen, no browser chrome)
5. Theme color: matches DaisyUI theme
6. Background color: matches app background
7. Start URL: `/portfolio`
8. Orientation: `any`

## Requirement 2: App Icons

1. Generate icon set: 192x192, 512x512 (minimum for Android + iOS)
2. Also: 180x180 (Apple touch icon)
3. Simple icon — company logo or stock chart symbol
4. Maskable icon variant for Android adaptive icons

## Requirement 3: iOS Meta Tags

1. `apple-mobile-web-app-capable` = yes
2. `apple-mobile-web-app-status-bar-style` = default
3. `apple-mobile-web-app-title` = "StockPlan"
4. Apple touch icon link
5. Viewport meta tag (already exists)

## Requirement 4: Service Worker

1. Basic service worker for offline shell caching
2. Cache: app shell (HTML, CSS, JS)
3. Network-first strategy for API/LiveView (always fetch fresh data)
4. Offline fallback: "You're offline — connect to update portfolio"
5. Registration in `app.js`

## Requirement 5: Install Prompt

1. Browser shows native "Add to Home Screen" prompt (automatic on Android)
2. iOS: user manually adds via Share → Add to Home Screen
3. Optional: in-app banner prompting installation on first visit

## Out of Scope

- Push notifications
- Background sync
- Offline data access (beyond cached shell)
- App store distribution
