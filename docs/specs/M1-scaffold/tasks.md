# Tasks: M1 — Project Scaffold

## Prerequisites

- None — M1 is the foundation module.
- Elixir, Erlang, and Hex must be installed on the development machine.
- Phoenix 1.8 installer must be available (`mix archive.install hex phx_new`).

---

## Task 1: Generate Phoenix Application

Generate the Phoenix 1.8 app with correct options and verify it compiles.

- [ ] 1.1 Run `mix phx.new stock_plan --database sqlite3 --no-mailer --no-dashboard` in the project root (generate into current directory or move files into place)
- [ ] 1.2 Verify the generated app uses `ecto_sqlite3` in `mix.exs`
- [ ] 1.3 Verify `phoenix_swoosh` and `phoenix_live_dashboard` are NOT in `mix.exs` dependencies
- [ ] 1.4 Run `mix deps.get` — all dependencies install without errors
- [ ] 1.5 Run `mix compile` — zero warnings from application code

## Task 2: Configure HTTP Server and Port

Ensure Bandit is the HTTP adapter and the app listens on port 4002.

- [ ] 2.1 Verify `bandit` is in `mix.exs` dependencies (Phoenix 1.8 should include it by default)
- [ ] 2.2 Check if generated `config/dev.exs` already configures Bandit. If yes, leave it as-is. Only add `adapter: Bandit.PhoenixAdapter` if the generated config uses a different adapter.
- [ ] 2.3 Update `config/dev.exs` to set `http: [ip: {127, 0, 0, 1}, port: 4002]` on the Endpoint
- [ ] 2.4 Update `config/test.exs` to set port 4002 and `server: false`
- [ ] 2.5 Run `mix phx.server` — verify server starts and logs show port 4002

## Task 3: Configure SQLite Database Path

Set the database path to `tmp/stock_plan_dev.db` and verify DB lifecycle commands.

- [ ] 3.1 Update `config/dev.exs` to set `database: Path.expand("../tmp/stock_plan_dev.db", __DIR__)`
- [ ] 3.2 Update `config/test.exs` to set `database: Path.expand("../tmp/stock_plan_test.db", __DIR__)` with `pool: Ecto.Adapters.SQL.Sandbox`
- [ ] 3.3 Verify `tmp/` is in `.gitignore`
- [ ] 3.4 Run `mix ecto.create` — database file created at `tmp/stock_plan_dev.db`
- [ ] 3.5 Run `mix ecto.migrate` — succeeds (no pending migrations yet)
- [ ] 3.6 Run `mix ecto.reset` — drops, recreates, and migrates without errors

## Task 4: Verify Tailwind v4

Confirm Tailwind v4 is configured and CSS compiles correctly.

- [ ] 4.1 Verify `tailwind` dependency in `mix.exs` and its version config (Phoenix 1.8 should default to v4)
- [ ] 4.2 Verify `assets/css/app.css` exists with Tailwind directives
- [ ] 4.3 Start dev server, load root page in browser — confirm CSS is applied (no unstyled flash)
- [ ] 4.4 Add a Tailwind utility class to the root page and verify it renders correctly

## Task 5: Create Root Route with LiveView

Add the root route and landing page LiveView to validate the full stack.

- [ ] 5.1 Create `lib/stock_plan_web/live/home_live.ex` with mount/render callbacks
- [ ] 5.2 Render heading "Stock Plan Manager" with Tailwind classes (`text-3xl font-bold` etc.)
- [ ] 5.3 Add brief description paragraph: "RSU, ESPP, and Stock Option management."
- [ ] 5.4 Update `lib/stock_plan_web/router.ex` — add `live "/", HomeLive` in the browser scope
- [ ] 5.5 Replace the root route to point to HomeLive while preserving the generated layout/component structure (`core_components.ex`, `layouts/`). Do not delete generated layout infrastructure.
- [ ] 5.6 Run `mix phx.server` — visit `http://localhost:4002/` — page renders with correct content and styling

## Task 6: Verify Directory Structure

Ensure the directory layout matches CLAUDE.md conventions.

- [ ] 6.1 Confirm `lib/stock_plan/` exists (business logic home — empty for now)
- [ ] 6.2 Confirm `lib/stock_plan_web/live/` exists with `home_live.ex`
- [ ] 6.3 Confirm `lib/stock_plan_web/controllers/` exists
- [ ] 6.4 Confirm `lib/stock_plan_web/components/` exists with `core_components.ex` and `layouts/`
- [ ] 6.5 Confirm `priv/repo/migrations/` exists
- [ ] 6.6 Confirm `config/` has `config.exs`, `dev.exs`, `test.exs`, `runtime.exs`
- [ ] 6.7 Confirm `assets/css/app.css` and `assets/js/app.js` exist

## Task 7: Verify Module Naming

Confirm all generated module names match the expected convention.

- [ ] 7.1 Verify `StockPlan` module in `lib/stock_plan/application.ex`
- [ ] 7.2 Verify `StockPlan.Repo` module in `lib/stock_plan/repo.ex`
- [ ] 7.3 Verify `StockPlanWeb` module in `lib/stock_plan_web.ex`
- [ ] 7.4 Verify `StockPlanWeb.Endpoint` module in `lib/stock_plan_web/endpoint.ex`
- [ ] 7.5 Verify OTP app name is `:stock_plan` in `mix.exs`

## Task 8: Run Full Verification

End-to-end check that everything works together.

- [ ] 8.1 From a clean state: `mix deps.get && mix ecto.reset && mix compile` — zero application warnings
- [ ] 8.2 `mix test` — all generated tests pass with zero failures
- [ ] 8.3 `mix phx.server` — server boots on port 4002
- [ ] 8.4 Browser: `http://localhost:4002/` — renders "Stock Plan Manager" with Tailwind styling
- [ ] 8.5 Browser: verify LiveView WebSocket connection is established (check browser devtools or LiveView debug)

---

## Notes

- **Implementation priority**: Tasks 1-3 are the critical path (app generation + config). Tasks 4-7 are verification. Task 8 is the final end-to-end check.
- **Key constraint**: Phoenix 1.8 defaults should handle most of the configuration (Bandit, Tailwind v4, LiveView). The main overrides are port number and DB path.
- **Testing approach**: M1 is primarily verified manually (boot + browse). Automated testing starts meaningfully in M2.
- **Risk**: If the installed Phoenix version is < 1.8, Bandit and Tailwind v4 may not be defaults. Verify `mix phx.new --version` before starting.

---

## Definition of Done

M1 is complete when ALL of the following are true:

- [ ] `mix test` passes with zero failures
- [ ] `mix compile` produces zero application warnings
- [ ] `http://localhost:4002/` renders custom "Stock Plan Manager" root page
- [ ] SQLite DB creates at `tmp/stock_plan_dev.db` via `mix ecto.create`
- [ ] `mix ecto.reset` completes without errors
- [ ] Git repo is clean — all scaffold files committed, no untracked artifacts
- [ ] Ready for M2 — `priv/repo/migrations/` exists, `StockPlan.Repo` is operational, new migrations can be added
