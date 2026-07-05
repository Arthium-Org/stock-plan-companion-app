# Runbook — Stock Plan Manager

## Quick Start

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server                        # http://localhost:4002 — FX rates load automatically on boot
```

---

## Multi-User Testing

Single-tenant app with SQLite. Each user gets their own DB file via `DB_USER` env var.

### Set Up a New User

```bash
DB_USER=user1 mix ecto.create
DB_USER=user1 mix ecto.migrate
DB_USER=user1 mix phx.server          # FX rates load automatically on boot
```

### Switch Between Users

```bash
# Stop current server (Ctrl+C), then:
DB_USER=user2 mix phx.server
```

### Available DB Files

| Env Var | DB File | Notes |
|---|---|---|
| (none) | `tmp/stock_plan_dev.db` | Default |
| `DB_USER=user1` | `tmp/stock_plan_user1.db` | SampleUser-1 |
| `DB_USER=user2` | `tmp/stock_plan_user2.db` | SampleUser-2 |
| `DB_USER=user3` | `tmp/stock_plan_user3.db` | SampleUser-3 |
| `DB_USER=user4` | `tmp/stock_plan_user4.db` | SampleUser-4 |

### Reset a User's Data

```bash
DB_USER=user2 mix ecto.reset
DB_USER=user2 mix phx.server          # restart — FX rates reseed automatically on boot
```

---

## Sample Data

Located in `docs/Sample-Data/`:

| User | BH | G&L | Holdings | Notes |
|---|---|---|---|---|
| SampleUser-1 | Yes | 2023, 2024, 2025 | No | All sold, no current holdings |
| SampleUser-2 | Yes | 2025, 2026 | Yes (RSU only) | RSU only, no ESPP |
| SampleUser-3 | Yes | — | Yes (ESPP + RSU) | Has both ESPP and RSU holdings |
| SampleUser-4 | TBD | TBD | TBD | — |

---

## Upload Order

1. **Benefit History** — creates origins, tranches, sales in Silver
2. **G&L Expanded** (optional) — enriches vest FMV, sale prices, RSU allocations
3. **Holdings (ByBenefitType)** — enriches sellable_qty, cost_basis on tranches

Upload at http://localhost:4002/upload

---

## Common Commands

```bash
# Development
mix phx.server                         # Start server (port 4002)
mix compile --warnings-as-errors       # Compile with strict warnings
mix format --check-formatted           # Check formatting

# Database
mix ecto.create                        # Create SQLite DB
mix ecto.migrate                       # Run pending migrations
mix ecto.reset                         # Drop + recreate + migrate
# FX rates load automatically on every boot from priv/fx/fx_rates.json
# (StockPlan.FX.Sync.seed_from_bundle/0) — no manual seed command needed

# Testing
mix test                               # Run all tests
mix test test/stock_plan/ingestion/    # Run ingestion tests only
mix test --exclude external            # Skip external API tests

# Rebuild Silver from Bronze (no re-upload needed)
mix run -e 'StockPlan.Ingestions.rebuild("default")'

# With specific user DB:
DB_USER=user3 mix run -e 'StockPlan.Ingestions.rebuild("default")'
```

---

## Troubleshooting

### Port 4002 already in use
```bash
lsof -i :4002 -t | xargs kill -9
```

### FX rates missing (INR toggle shows nil)
FX rates seed automatically from `priv/fx/fx_rates.json` on every boot — restart the
server (`mix phx.server`) to reseed, then rebuild Silver to apply FX:
```bash
mix run -e 'StockPlan.Ingestions.rebuild("default")'
```

### Holdings upload fails with "Something went wrong"
Check server logs. Common cause: no Benefit History uploaded yet. Upload BH first, then Holdings.

### Duplicate file error on re-upload
Same file (by SHA256 hash) was already uploaded. To re-ingest, reset the DB:
```bash
mix ecto.reset
```
Restart the server afterward — FX rates reseed automatically on boot.

### Tests use separate DB
Test DB is `tmp/stock_plan_test.db` — isolated from dev. `DB_USER` does not affect tests.
