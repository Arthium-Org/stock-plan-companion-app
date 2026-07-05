# Contributing to Stock Plan Manager

Thanks for your interest in contributing! Stock Plan Manager is a lightweight,
single-tenant, self-hosted app for managing equity compensation (RSU / ESPP /
Stock Options). See [README.md](README.md) for what it does and why.

## Local Setup

```bash
mix deps.get         # install dependencies
mix ecto.migrate      # create/migrate the SQLite database
mix phx.server         # start the app on http://localhost:4002
```

The dev database lives at `tmp/stock_plan_dev.db` (SQLite, gitignored).

## Before You Open a PR

Run the full precommit checklist locally — this is the same gate CI runs:

```bash
mix compile --warnings-as-errors   # must compile with zero warnings
mix format                         # format all Elixir + HEEx files
mix test                           # run the automated test suite
```

(All three are also available as a single alias: `mix precommit`.)

If your change touches **ingestion, portfolio, tax, or FX** logic, also run the
golden-file manual test harness before and after your change to confirm nothing
regressed:

```bash
mix manual_test
# or
./scripts/manual_test.sh
```

This validates Portfolio, Capital Gains, and Schedule FA output against known-good
sample data. See `.cursor/skills/manual-test/SKILL.md` for details on interpreting
output and adding new test users.

## Code Conventions

This is a mature, opinionated codebase. Please follow the conventions already in
place (see `CLAUDE.md` for the full reference):

- **SafeDecimal for all decimal fields.** SQLite has no native `DECIMAL` type;
  all financial decimals are stored as TEXT via the custom `SafeDecimal` Ecto
  type. Never use `:decimal` directly on a schema field.
- **Context modules own all DB access.** No raw `Repo` calls from LiveViews,
  schemas, or other layers — always go through a context module
  (`lib/stock_plan/*.ex`).
- **No raw SQL outside migrations.** Use the `Ecto.Query` DSL; `execute/1` is
  reserved for `priv/repo/migrations/`.
- **Every module needs a `@moduledoc`; every public function needs `@doc` and
  `@spec`.**
- **Migrations are append-only.** Never edit an existing migration — always
  generate a new one with `mix ecto.gen.migration`.
- **Schema modules contain zero business logic** — only `use Ecto.Schema`,
  field definitions, and `changeset/2`.

Run `mix format` before committing; the formatter config (`.formatter.exs`)
includes the `Phoenix.LiveView.HTMLFormatter` plugin for `.heex` templates.

## Filing Issues

Please use the issue templates:

- **Bug report** — for something that doesn't work as expected.
- **Feature request** — for something you'd like to see added.

Both are available from the "New Issue" button on GitHub.

## Opening Pull Requests

1. Fork the repo and create a branch from `main`.
2. Make your change, following the conventions above.
3. Run the precommit checklist (and `mix manual_test` if applicable).
4. Open a PR — the PR template will walk you through the checklist and a
   reminder to never include real financial data or PII in a diff.

This project handles other people's tax and financial data as an offline,
self-hosted tool. **Never commit real account numbers, real broker exports, or
any other real financial PII** — use synthetic or redacted data in tests,
screenshots, and examples.
