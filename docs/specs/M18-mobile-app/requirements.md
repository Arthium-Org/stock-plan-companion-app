# Requirements: M18 — Mobile App (React Native)

## Introduction

Native mobile app for iOS and Android consuming the REST API (M17). Mirrors the web app features with mobile-optimized UX.

---

## Requirement 1: Framework

1. React Native with Expo (managed workflow)
2. Cross-platform: iOS + Android from single codebase
3. TypeScript
4. Separate repo or monorepo with the Phoenix backend

## Requirement 2: Screens (Phase 1)

### Portfolio Screen
1. Summary cards (Total, Current, Potential)
2. ESPP section: collapsible enrollments → purchases
3. RSU section: collapsible grants → tranches
4. Pull-to-refresh for live price update
5. USD/INR toggle

### Tax Centre Screen
1. Tab: Schedule FA (year picker, table, share/export CSV)
2. Tab: Capital Gains (FY picker, summary cards, detail table)

### Sell Advisor Screen
1. Input: shares/USD/INR selector + amount
2. 2 basket cards with expand/collapse lot detail
3. Share/export CSV per basket

### Upload Screen
1. File picker for BH, G&L, Holdings XLSX
2. Upload progress indicator
3. Upload history

## Requirement 3: Navigation

1. Bottom tab bar: Portfolio | Tax | Sell | Upload
2. Each tab is a stack navigator

## Requirement 4: Data Layer

1. REST API client (axios or fetch)
2. API base URL configurable (dev: localhost:4002, prod: server URL)
3. API key stored in secure storage (Expo SecureStore)
4. Error handling: network errors, auth errors, server errors

## Requirement 5: Styling

1. NativeWind (Tailwind for React Native) or React Native Paper
2. Dark/light theme support
3. Consistent with web app design language

## Requirement 6: Offline

1. Cache last-fetched portfolio data locally
2. Show cached data with "Last updated: X" timestamp
3. Offline banner when no connection

## Out of Scope (Phase 1)

- Push notifications
- Biometric auth
- Widget (iOS/Android)
- App Store / Play Store distribution (TestFlight/internal only)
