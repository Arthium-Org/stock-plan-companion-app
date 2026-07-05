# Design: M27 — Marketing Site (Cloud Portal — Public)

## Architecture

```
Internet
   │
   ▼
┌─────────────────────────────────────────────────────────┐
│  StockPlanPortal (cloud Phoenix app)                    │
│  ─────────────────────────────────────────────────────  │
│  Public LiveViews / controllers                         │
│    /              LandingLive                           │
│    /download      DownloadLive + manifest.json          │
│    /pricing       PricingLive                           │
│    /docs/*        DocsController (Markdown → HTML)      │
│    /news/*        NewsController                        │
│    /privacy       StaticLive                            │
│  Account LiveViews (M28 plugs)                          │
│    /account/*     RegisterLive, LoginLive, Dashboard    │
└─────────────────────────────────────────────────────────┘
         │
         │  (M28) Postgres — users, subscriptions only
         │  (M29) FX rates master — no user financial data
         │
         ▼
   CDN (R2 / S3 / GitHub Releases)
     └── stock_plan-1.5.0-macos_aarch64
     └── stock_plan-1.5.0-windows_x86_64.exe
```

**Separate from desktop app:**

```
User machine
   └── StockPlan (local Phoenix + SQLite) — NOT deployed to cloud
```

---

## Repository Layout

Add a sibling Phoenix app under `portal/` (umbrella optional; standalone app is fine):

```
portal/
├── lib/portal/
│   ├── application.ex
│   └── content/              # Markdown rendering
│       ├── docs.ex
│       └── news.ex
├── lib/portal_web/
│   ├── live/
│   │   ├── landing_live.ex
│   │   ├── download_live.ex
│   │   └── pricing_live.ex
│   ├── controllers/
│   │   ├── docs_controller.ex
│   │   ├── news_controller.ex
│   │   └── manifest_controller.ex
│   └── components/
│       └── layouts/
├── priv/content/
│   ├── docs/
│   │   ├── schedule-fa.md
│   │   ├── schedule-fsi.md
│   │   ├── schedule-tr.md
│   │   ├── capital-gains.md
│   │   ├── etrade-upload.md
│   │   └── getting-started.md
│   └── news/
│       └── *.md
├── priv/static/
│   └── images/               # Screenshots, OG images
└── config/
```

Desktop app repo root (`stock_plan/`) unchanged except M30 client modules.

---

## Content Pipeline

### Markdown Rendering

Use `Earmark` (already common in Phoenix) + optional syntax highlighting for code blocks.

```elixir
defmodule Portal.Content.Docs do
  @doc "List all docs with slug, title, order."
  def all_docs()

  @doc "Render doc by slug → {html, front_matter}."
  def render!(slug)
end
```

Front matter (YAML):

```markdown
---
title: Schedule FA — Foreign Assets Disclosure
summary: Calendar-year reporting for US equity held via RSU/ESPP
order: 1
tags: [schedule-fa, foreign-assets]
---

## Introduction
...
```

### News Articles

Same pipeline; sorted by `published_at` from front matter.

---

## Download Manifest

**Source of truth:** `portal/priv/releases/manifest.json` committed to repo, updated on each desktop release (M19 build CI step).

`ManifestController` serves JSON with cache headers (`max-age=300`).

Download URLs point to CDN — not served by Phoenix binary (files too large).

---

## Page Designs

### Landing (`/`)

Sections:
1. Hero — headline, subhead, Download + Docs buttons
2. Problem — Indian resident + US RSU/ESPP tax complexity
3. Features — 3 cards: Schedule FA, Capital Gains, Sell Advisor
4. Local-first — diagram: data stays on device
5. Pricing teaser → `/pricing`
6. Footer

### Download (`/download`)

- Platform tabs: macOS (Apple Silicon / Intel) | Windows
- Version selector if multiple versions in manifest (default: latest)
- Checksum copy button
- Install instructions per platform

### Docs layout

Shared layout: left sidebar (doc nav), main content, right "In this article" TOC from headings.

---

## Account Page Shell (M28 fills in)

Router scope:

```elixir
scope "/account", PortalWeb do
  pipe_through [:browser]

  live "/register", Account.RegisterLive
  live "/login", Account.LoginLive
end

scope "/account", PortalWeb do
  pipe_through [:browser, :require_auth]

  live "/", Account.DashboardLive
  live "/billing", Account.BillingLive
end
```

M27 delivers layout components and routes; M28 implements auth plugs and dashboard data.

---

## Styling

- Tailwind v4 + DaisyUI (match desktop app design language)
- Shared color tokens where practical (document in portal README)
- Docs: prose plugin or `@tailwindcss/typography` equivalent for readable long-form

---

## Deployment

| Component | Target |
|-----------|--------|
| Portal Phoenix | Fly.io / Gigalixir / Railway |
| Postgres | Managed Postgres (M28 schema) |
| Static assets | `phx.digest` via CDN or Fly static |
| Desktop binaries | Cloudflare R2 or GitHub Releases |

**Domains (example):**
- `stockplan.example.com` — portal
- `api.stockplan.example.com` — optional; or `/api/v1` on same host

**Port:** 4003 in dev (desktop stays 4002)

---

## Security

- No CORS needed for public pages
- CSP headers on docs (no inline scripts except LiveView)
- Download links: HTTPS CDN only; manifest checksums for integrity verification
- Rate limit on `/account/register` (M28)

---

## Migration from Current App

Current `StockPlanWeb.GuideLive` E*Trade content → move to `portal/priv/content/docs/etrade-upload.md`.

Current `HomeLive` local welcome flow stays in desktop app; portal landing replaces it for **web** visitors only.
