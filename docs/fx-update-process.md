# FX Rate Update Process (Maintainer Runbook)

Stock Plan Manager fetches USD/INR exchange rates as a **static JSON file served
from this repo's `main` branch** — there is no hosted FX API. This keeps the
project fully static/serverless while still letting every self-hosted instance
pick up new rates automatically.

This document describes the maintainer's **monthly manual update** process.
Automating this commit (a scheduled GitHub Action that opens/merges the update
itself) is tracked as **FX-05** and deferred to a future release (v1.1) — for
now, the maintainer edits and commits the file by hand.

## How the runtime fetch works

- The canonical rates file lives at `priv/fx/fx_rates.json` in this repo.
- On boot, each running instance fetches the latest copy from the GitHub raw
  URL for this file on `main` (e.g.
  `https://raw.githubusercontent.com/{ORG}/{REPO}/main/priv/fx/fx_rates.json`)
  and upserts the rows into its local SQLite database.
- If the fetch fails (offline, GitHub unreachable, etc.), the app silently
  falls back to the rates bundled in the release — no error is shown to the
  user, since the app already has last-known-good rates and will pick up the
  new ones on a future successful boot.
- Because the raw URL is pinned to `main` (not a version tag), **a single
  commit to `main` is all it takes to reach every running instance** — no app
  release or version bump is required.

## Data sources

Reproduce these sources each month (the values previously lived in
`priv/repo/fx_seed_data.exs`, which has been retired in favor of the JSON
file):

| Field | Source | Notes |
|---|---|---|
| `tt_buying_rate_month_end` | SBI TT Buy rate, last day of month | See `sahilgupta/sbi-fx-ratekeeper` (GitHub) or `taxroutine.com` |
| `standard_rate_month_end` | RBI reference rate, last day of month | `rbi.org.in/scripts/ReferenceRateArchive.aspx` |
| `standard_rate_month_avg` | Monthly average market rate | `x-rates.com` (USD/INR monthly average) |

Not every source publishes every month reliably — use `null` for any field
you cannot confirm rather than guessing a value.

## Step-by-step: publishing a new month's rates

1. **Gather the rates** for the month that just closed, from the three sources
   above.

2. **Open `priv/fx/fx_rates.json`** and append a new object to the `rates`
   array, following the existing schema (illustrative example — use real
   values from your own lookup, not the placeholders below):

   ```json
   {
     "year_month": "2026-07",
     "tt_buying_rate_month_end": "85.00",
     "standard_rate_month_end": "85.05",
     "standard_rate_month_avg": "84.90"
   }
   ```

   - `year_month` — `YYYY-MM` for the month just closed.
   - All three rate fields are **strings** (SafeDecimal-compatible), or
     `null` if a source has no value for that month.
   - Append to the end of the `rates` array; do not reorder or remove
     existing entries — the file is a growing historical dataset.

3. **Bump the top-level `updated` field** to today's date (`YYYY-MM-DD`), so
   the app can tell the fetched file is newer than what it has locally.

4. **Commit and push directly to `main`**:

   ```bash
   git add priv/fx/fx_rates.json
   git commit -m "chore(fx): add YYYY-MM rates"
   git push origin main
   ```

That's it — no release, no tag, no deploy. The next time any self-hosted
instance boots (or on its periodic re-check, if implemented), it fetches this
file from `main` and upserts the new row.

## Notes

- **No real account numbers or personal financial data ever belong in this
  file or this doc.** The examples above use illustrative placeholder rates
  only.
- If a source is temporarily unavailable, it's fine to publish a month with
  one or two `null` fields and backfill later — the upsert is idempotent, so
  re-publishing the same `year_month` with additional fields filled in is
  safe.
- Automating this entire process (scheduled fetch + auto-commit via GitHub
  Action) is **FX-05**, planned for v1.1 — not implemented yet.
