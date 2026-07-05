# M17 — Formal Disposition (Amendment)

**Date:** 2026-06-11  
**Status:** Locked

## Decision

M17 REST API endpoints (portfolio, tax, upload, sell advisor, market data) are **localhost-only** inside the desktop app bundle. They SHALL **NOT** be deployed to the cloud portal.

## Rationale

The product is **local-first**: all financial data (Benefit History, G&L, portfolio, tax exports) stays on the user's machine in SQLite. Cloud services (M27–M31) handle marketing, auth, subscriptions, and FX rate sync only.

## Scope

| Endpoint group | Deployment |
|----------------|------------|
| `/api/portfolio/*` | Localhost `:4002` only (optional; future mobile companion) |
| `/api/tax/*` | Localhost only |
| `/api/upload/*` | Localhost only |
| `/api/sell/*` | Localhost only |
| `/api/price/*` | Localhost only |
| `/api/v1/auth/*` | Cloud portal (M28) |
| `/api/v1/fx/*` | Cloud portal (M29) |

## Future

M17 MAY be repurposed as a **localhost API** for a future on-device mobile client that talks to the same local Phoenix server — not a remote cloud API.

## Related milestones

- M28 explicitly rejects cloud portfolio/tax/upload
- M30 desktop licensing uses M28/M29 cloud endpoints only
