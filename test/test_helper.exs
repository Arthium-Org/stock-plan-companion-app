# Local default mirrors CI (.github/workflows/ci.yml runs `mix test --exclude
# requires_fixtures`): the fixture-dependent suites are gated on Phase 5 synthetic
# data and are excluded by default so a plain `mix test` is green + fast. Run them
# explicitly with `mix test --include requires_fixtures` once fixtures land.
ExUnit.start(exclude: [:external, :requires_fixtures])
Ecto.Adapters.SQL.Sandbox.mode(StockPlan.Repo, :manual)

# Seed the isolated test profile so authenticated routes (/upload, /portfolio) do
# not redirect to onboarding in a clean environment (the check_profile plug only
# tests for file existence). Path comes from config/test.exs :profile_path.
if profile_path = Application.get_env(:stock_plan, :profile_path) do
  File.mkdir_p!(Path.dirname(profile_path))
  File.write!(profile_path, "{}")
end
