# Tasks: M16 — Progressive Web App (PWA)

## Milestone 1: Manifest + Icons

- [ ] 1.1 Create `priv/static/manifest.json`
- [ ] 1.2 Generate icon set (192, 512, 180, maskable)
- [ ] 1.3 Place icons in `priv/static/icons/`
- [ ] 1.4 Add manifest link to `root.html.heex`
- [ ] 1.5 Add iOS meta tags to `root.html.heex`
- [ ] 1.6 Add theme-color meta tag

## Milestone 2: Service Worker

- [ ] 2.1 Create `priv/static/sw.js`
- [ ] 2.2 Cache app shell (CSS, JS, icons)
- [ ] 2.3 Network-first fetch strategy
- [ ] 2.4 Register service worker in `app.js`
- [ ] 2.5 Configure Phoenix endpoint to serve sw.js from root path

## Milestone 3: Verification

- [ ] 3.1 Android Chrome: "Add to Home Screen" prompt appears
- [ ] 3.2 Android: app opens in standalone mode (no browser bar)
- [ ] 3.3 iOS Safari: Share → Add to Home Screen works
- [ ] 3.4 iOS: app opens in standalone mode
- [ ] 3.5 Chrome DevTools → Application → Manifest shows correct data
- [ ] 3.6 Lighthouse PWA audit passes
- [ ] 3.7 All existing tests still pass

## Definition of Done

- [ ] App installable on Android (Chrome prompt)
- [ ] App installable on iOS (manual add)
- [ ] Opens in standalone mode (no browser chrome)
- [ ] App icon on home screen
- [ ] Offline: shows fallback message (not browser error)
- [ ] All tests pass
