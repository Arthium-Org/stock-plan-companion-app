# Tasks: M27 — Marketing Site (Cloud Portal — Public)

## Prerequisites

- Decision on domain name and CDN for desktop artifacts
- M19: at least one Windows `.exe` and Mac build available for manifest
- M28/M29 can proceed in parallel after portal scaffold exists

---

## Milestone 1: Portal App Scaffold

- [ ] 1.1 Create `portal/` Phoenix app (`mix phx.new portal --no-mailer` or umbrella app)
- [ ] 1.2 Configure dev port 4003, separate from desktop (4002)
- [ ] 1.3 Add Tailwind v4 + DaisyUI matching desktop theme tokens
- [ ] 1.4 Root layout: nav (Docs, Download, Pricing, News, Account), footer
- [ ] 1.5 `mix compile` — pass

## Milestone 2: Landing & Pricing

**Files:** `portal/lib/portal_web/live/landing_live.ex`, `pricing_live.ex`

- [ ] 2.1 Landing page with hero, features, local-first trust section
- [ ] 2.2 Pricing page with Trial + Individual tier placeholders (prices TBD)
- [ ] 2.3 Mobile-responsive layout
- [ ] 2.4 Manual browser check — `/`, `/pricing`

## Milestone 3: Download Page & Manifest

**Files:** `download_live.ex`, `manifest_controller.ex`, `priv/releases/manifest.json`

- [ ] 3.1 Create manifest JSON schema and seed with 1.4+ release URLs
- [ ] 3.2 `GET /download/manifest.json` endpoint
- [ ] 3.3 Download page: platform selector, version, checksum, size, link
- [ ] 3.4 Post-install instructions (Mac + Windows)
- [ ] 3.5 Document manifest update step in M19 release checklist

## Milestone 4: Content Pipeline

**Files:** `portal/lib/portal/content/docs.ex`, `news.ex`

- [ ] 4.1 Add Earmark dependency
- [ ] 4.2 Markdown loader with YAML front matter parser
- [ ] 4.3 `DocsController` — index + show by slug
- [ ] 4.4 `NewsController` — index + show by slug (tag filter deferred Phase 1b)
- [ ] 4.5 Docs layout: sidebar nav, TOC from headings
- [ ] 4.6 `mix compile` — pass
- [ ] 4.7 Content pipeline smoke tests in CI (Markdown loader + front matter parse)

## Milestone 5: Documentation Content

**Dir:** `portal/priv/content/docs/`

- [ ] 5.1 Write `getting-started.md`
- [ ] 5.2 Write `schedule-fa.md` (field mapping + example)
- [ ] 5.3 Write `schedule-fsi.md`
- [ ] 5.4 Write `schedule-tr.md`
- [ ] 5.5 Write `capital-gains.md`
- [ ] 5.6 Migrate E*Trade guide → `etrade-upload.md`
- [ ] 5.7 Cross-links between docs and to pricing/download

## Milestone 6: Tax News Content

**Dir:** `portal/priv/content/news/`

- [ ] 6.1 Write 5 launch articles (evergreen foreign-asset / ITR topics)
- [ ] 6.2 News index (newest first; tag filtering deferred to Phase 1b)
- [ ] 6.3 Article template with OG meta tags

## Milestone 7: Legal & SEO

- [ ] 7.1 Privacy policy page (`/privacy`)
- [ ] 7.2 Terms of service page (`/terms`)
- [ ] 7.3 `robots.txt`, `sitemap.xml` generator
- [ ] 7.4 Per-page meta titles and descriptions
- [ ] 7.5 OG tags for docs and news

## Milestone 8: Account Shell (M28 handoff)

- [ ] 8.1 Account route stubs: register, login, dashboard layouts
- [ ] 8.2 Placeholder dashboard: "Sign in to view subscription" (wired in M28)
- [ ] 8.3 Router scopes documented for M28 auth plugs

## Milestone 9: Deploy

- [ ] 9.1 Production config (`PORTAL_HOST`, CDN URLs)
- [ ] 9.2 Fly.io (or chosen host) deploy config
- [ ] 9.3 HTTPS + custom domain
- [ ] 9.4 Smoke test production URLs

---

## Definition of Done

- All public routes live on cloud deploy
- Docs and news render from Markdown
- Download manifest points to real Mac + Windows artifacts
- No upload or portfolio routes exist on portal
- Account pages exist as shells for M28
