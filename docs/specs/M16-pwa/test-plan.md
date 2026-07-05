# Test Plan: M16 — Progressive Web App (PWA)

---

## TP-1: Manifest (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Chrome DevTools → Application → Manifest | All fields populated correctly |
| TP-1.2 | Icons listed | 192, 512, maskable visible |
| TP-1.3 | Start URL | /portfolio |
| TP-1.4 | Display mode | standalone |

## TP-2: Android Install (Manual Device/Emulator)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Visit site in Chrome | "Add to Home Screen" banner appears |
| TP-2.2 | Install | App icon on home screen |
| TP-2.3 | Open from home screen | Standalone mode, no browser bar |
| TP-2.4 | Navigate pages | Portfolio, Tax, Sell all work |

## TP-3: iOS Install (Manual Device)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Visit site in Safari | No errors |
| TP-3.2 | Share → Add to Home Screen | App icon appears |
| TP-3.3 | Open from home screen | Standalone mode |
| TP-3.4 | Status bar | Correct color |

## TP-4: Service Worker (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | DevTools → Application → Service Workers | Registered and active |
| TP-4.2 | Go offline | Shows fallback, not browser error |
| TP-4.3 | Come back online | App resumes normally |

## TP-5: Lighthouse (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Run Lighthouse PWA audit | Passes installable check |
| TP-5.2 | Icons | Correct sizes detected |
| TP-5.3 | Manifest | Valid |

---

## Test Count: ~15 manual tests
