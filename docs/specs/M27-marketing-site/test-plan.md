# Test Plan: M27 — Marketing Site (Cloud Portal — Public)

---

## TP-1: Landing & Navigation (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | GET `/` | 200, hero + Download CTA visible |
| TP-1.2 | Click Download | Navigates to `/download` |
| TP-1.3 | Click Docs | Navigates to `/docs` |
| TP-1.4 | Mobile viewport | Layout readable, nav accessible |
| TP-1.5 | Trust messaging | "Data stays on your computer" visible on landing |

## TP-2: Download Page (Manual + Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | GET `/download` | Mac and Windows sections present |
| TP-2.2 | GET `/download/manifest.json` | Valid JSON, `latest` version, all 3 platform keys |
| TP-2.3 | Manifest checksum | SHA-256 matches actual file on CDN |
| TP-2.4 | Download link | HTTPS URL resolves (HEAD request 200) |
| TP-2.5 | No upload UI | Page has no file input for brokerage data |

**Automated:** `test/portal_web/controllers/manifest_controller_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.A1 | Manifest endpoint | Returns 200, content-type application/json |
| TP-2.A2 | Schema validation | Required fields present per requirements |

## TP-3: Documentation (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | GET `/docs` | Index lists all 6 guides |
| TP-3.2 | GET `/docs/schedule-fa` | Renders HTML, field mapping table present |
| TP-3.3 | GET `/docs/schedule-fsi` | 200 |
| TP-3.4 | GET `/docs/schedule-tr` | 200 |
| TP-3.5 | GET `/docs/capital-gains` | 200 |
| TP-3.6 | GET `/docs/etrade-upload` | E*Trade steps present |
| TP-3.7 | GET `/docs/getting-started` | Desktop install steps, no web upload |
| TP-3.8 | Invalid slug | 404 |
| TP-3.9 | Sidebar nav | All docs linked, current doc highlighted |

**Automated:** `test/portal/content/docs_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.A1 | `all_docs/0` | Returns 6 entries |
| TP-3.A2 | `render!/1` valid slug | Returns HTML string |
| TP-3.A3 | `render!/1` invalid | Raises or returns error |

## TP-4: Tax News (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | GET `/news` | ≥ 5 articles listed, newest first |
| TP-4.2 | GET `/news/:slug` | Article renders with title and date |
| TP-4.3 | Tag filter | Deferred Phase 1b |
| TP-4.4 | OG tags | View source: og:title present on article |

## TP-5: Pricing & Legal (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | GET `/pricing` | Trial + Individual tiers shown |
| TP-5.2 | GET `/privacy` | Policy mentions no financial data collection |
| TP-5.3 | GET `/terms` | 200 |
| TP-5.4 | Footer links | All footer links resolve |

## TP-6: SEO (Automated + Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | GET `/robots.txt` | 200 |
| TP-6.2 | GET `/sitemap.xml` | Contains docs and news URLs |
| TP-6.3 | Unique titles | No duplicate `<title>` across main pages |

## TP-7: Security & Scope (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | No `/upload` route | 404 on portal |
| TP-7.2 | No `/portfolio` route | 404 on portal |
| TP-7.3 | No `/tax` route | 404 on portal |
| TP-7.4 | HTTPS redirect | HTTP redirects to HTTPS in prod |

## TP-8: Account Shell (Manual — pre-M28)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | GET `/account/register` | Registration form shell loads |
| TP-8.2 | GET `/account/login` | Login form shell loads |
| TP-8.3 | GET `/account` unauthenticated | Redirects to login (once M28 wired) |

---

## Regression

After M28/M29 integration:
- Re-run TP-7 (no product routes)
- Verify account dashboard shows license key without any financial fields
