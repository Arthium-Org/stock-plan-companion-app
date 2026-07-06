# Local default mirrors CI (.github/workflows/ci.yml runs `mix test --exclude
# requires_fixtures`): the fixture-dependent suites are gated on Phase 5 synthetic
# data and are excluded by default so a plain `mix test` is green + fast. Run them
# explicitly with `mix test --include requires_fixtures` once fixtures land.
ExUnit.start(exclude: [:external, :requires_fixtures])

# StockPlan.Application boots StockPlan.FX.Sync.seed_from_bundle/0 in an
# unawaited Task.start/1 (see lib/stock_plan/application.ex) so a real server
# boot is never blocked on it. That's fine at runtime, but it races every test
# in this suite: any :requires_fixtures test that reaches FX-dependent code
# (SilverBuilder's enrich_fx_rates/1, ScheduleFA's cross-validation, etc.)
# before that async seed finishes sees an empty FxMonthlyRate table and
# permanently persists nil sale_fx_rate/vest_fx_rate values for that Silver
# rebuild (enrich_fx_rates only fills rows where the fx field is currently
# nil, and Silver is fully rebuilt-and-re-enriched exactly once per ingest
# call). Confirmed empirically: the exact same ingest+build sequence
# non-deterministically produced fx_rate: nil vs. fx_rate: populated across
# separate `mix test` invocations, tracing to this boot-time race, not to any
# ScheduleFA FY-window logic. seed_from_bundle/0 reads only the local bundled
# JSON (no network) and upserts idempotently, so calling it synchronously here
# is safe and makes every FX-dependent test deterministic regardless of
# system/scheduler timing.
#
# MUST run before Sandbox.mode(:manual) below -- once manual mode is set,
# any query from a process that hasn't explicitly checked out a sandbox
# connection raises DBConnection.OwnershipError, which seed_from_bundle/0's
# blanket `rescue _ -> :ok` would silently swallow, making the seed a no-op
# that looks like success.
StockPlan.FX.Sync.seed_from_bundle()

Ecto.Adapters.SQL.Sandbox.mode(StockPlan.Repo, :manual)

# Seed the isolated test profile so authenticated routes (/upload, /portfolio) do
# not redirect to onboarding in a clean environment (the check_profile plug only
# tests for file existence). Path comes from config/test.exs :profile_path.
if profile_path = Application.get_env(:stock_plan, :profile_path) do
  File.mkdir_p!(Path.dirname(profile_path))
  File.write!(profile_path, "{}")
end
