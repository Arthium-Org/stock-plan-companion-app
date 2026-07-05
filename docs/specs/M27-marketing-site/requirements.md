# Requirements: M27 — Marketing Site (Cloud Portal — Public)

## Introduction

Deploy a **public-facing website** that promotes Stock Plan Manager, hosts downloads, help documentation, and tax news. The website does **not** host the product app and does **not** receive or store user financial data (Benefit History, G&L, portfolio, tax exports).

**Relationship to other milestones:**
- **M28** — Auth, trial, subscription (account pages on this site)
- **M29** — FX sync API (subscriber-only; linked from docs, consumed by desktop app)
- **M30** — Desktop app license + FX sync client (local)
- **M19** — Desktop executables (Mac + Windows) linked from `/download`

**Deployment model:** Separate cloud-deployed Phoenix app (`StockPlanPortal`). The local desktop app (`StockPlan`) is a different release artifact.

---

## Requirement 1: Site Identity & Trust

1. THE site SHALL communicate clearly: **"Your financial data stays on your computer."**
2. THE site SHALL NOT offer in-browser upload of Benefit History, G&L, or Holdings files
3. THE site SHALL NOT expose portfolio, tax centre, or sell-advisor UI
4. Privacy policy and terms pages SHALL state: no collection of brokerage files or tax computation inputs

## Requirement 2: Landing Page

1. THE site SHALL serve `/` as the product landing page
2. THE landing page SHALL include:
   - Value proposition (RSU / ESPP / foreign equity tax for Indian residents)
   - Key features: Schedule FA, Capital Gains, Sell Advisor (screenshots or static previews — no live user data)
   - "Download" CTA → `/download`
   - "Docs" CTA → `/docs`
   - "Pricing" CTA → `/pricing`
   - Trust line: local-first, data never uploaded
3. THE landing page SHALL be mobile-responsive

## Requirement 3: Download Page

1. THE site SHALL serve `/download` with installable artifacts for **macOS** and **Windows**
2. FOR EACH platform THE page SHALL show:
   - Latest version number (from release manifest)
   - Minimum OS version
   - File size and SHA-256 checksum
   - Direct download link (CDN URL)
3. THE site SHALL serve a machine-readable manifest at `/download/manifest.json`:
   ```json
   {
     "latest": "1.5.0",
     "releases": [
       {
         "version": "1.5.0",
         "published_at": "2026-06-01T00:00:00Z",
         "platforms": {
           "macos_aarch64": { "url": "...", "sha256": "...", "size_bytes": 0 },
           "macos_x86_64": { "url": "...", "sha256": "...", "size_bytes": 0 },
           "windows_x86_64": { "url": "...", "sha256": "...", "size_bytes": 0 }
         },
         "release_notes_url": "/news/stock-plan-1-5-0"
       }
     ]
   }
   ```
4. Windows artifact: `.exe` (existing 1.4 release pipeline). macOS: `.app` bundle or standalone binary per M19
5. THE download page SHALL include post-install steps: launch app → browser opens localhost → sign in / start trial

## Requirement 4: Pricing Page

1. THE site SHALL serve `/pricing` with subscription tiers (content may change; structure is fixed)
2. Phase 1 tiers displayed:
   - **Trial** — time-limited full access (duration configured in M28; TBD exact days)
   - **Individual** — annual subscription (price TBD)
3. THE page SHALL link to sign-up (`/account/register`) and account login
4. THE page SHALL NOT process payments inline on landing — checkout via M28 payment flow

## Requirement 5: Help Documentation

1. THE site SHALL serve `/docs` as documentation hub
2. THE site SHALL serve the following guides (Markdown source, rendered HTML):
   - `/docs/schedule-fa` — Calendar-year foreign asset disclosure
   - `/docs/schedule-fsi` — Financial-year foreign source income
   - `/docs/schedule-tr` — Tax relief / DTAA credit
   - `/docs/capital-gains` — STCG/LTCG for US equity from stock plans
   - `/docs/etrade-upload` — How to download Benefit History, G&L, Holdings from E*Trade
   - `/docs/getting-started` — Install desktop app, first upload, profile setup
3. EACH doc SHALL include:
   - Concept overview (who must file, which ITR schedule)
   - Period (CY vs FY)
   - Field mapping table (ITR field → app output)
   - Worked numeric example (synthetic data, not real user data)
   - CTA: "Generate in the desktop app" (no web app link)
4. Docs SHALL cross-link to [Indian Tax Rules](../../core/indian-tax-rules.md) concepts where relevant
5. Docs content SHALL live in repo as Markdown under `portal/priv/content/docs/` (or equivalent portal app path)

## Requirement 6: Tax News

1. THE site SHALL serve `/news` as a blog index (newest first)
2. THE site SHALL serve `/news/:slug` for individual articles
3. Articles SHALL focus on: foreign assets, Schedule FA, foreign income, DTAA, capital gains rule changes
4. Phase 1: minimum **5 evergreen articles** at launch + support for future posts
5. News content SHALL live as Markdown under `portal/priv/content/news/` with front matter (title, date, tags, summary)
6. News tag filtering (`#schedule-fa`, etc.) is **Phase 1b** — index only at launch; filtering deferred until article count grows

## Requirement 7: Legal & Footer

1. THE site SHALL serve `/privacy` and `/terms`
2. THE footer SHALL appear on all public pages with links: Docs, Download, Pricing, News, Privacy, Terms, Contact
3. Contact: support email address (configurable)

## Requirement 8: Account Pages (Shell — logic in M28)

1. THE site SHALL serve account routes (implementation delegated to M28):
   - `/account/register`
   - `/account/login`
   - `/account` — dashboard: subscription status, license key, download links, manage billing
2. Account pages SHALL NOT display or accept financial uploads

## Requirement 9: SEO & Metadata

1. EACH public page SHALL have unique `<title>` and meta description
2. Docs and news SHALL have Open Graph tags (title, description, optional image)
3. THE site SHALL serve `robots.txt` and `sitemap.xml` including docs and news URLs

## Requirement 10: Non-Functional

1. THE site SHALL target **< 2s** TTFB on cached static content
2. THE site SHALL run on HTTPS only in production
3. THE site SHALL NOT share a database with the desktop app's SQLite
4. Environment-specific config: `PORTAL_HOST`, CDN base URL for downloads, support email

---

## Out of Scope (M27)

- Payment processing (M28)
- Auth API implementation (M28)
- FX API (M29)
- Desktop app licensing client (M30)
- In-browser product app or file upload
- User forums or comments on news
- Multi-language (English only for Phase 1)
