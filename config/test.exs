import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :stock_plan, StockPlan.Repo,
  database: Path.expand("../tmp/stock_plan_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  after_connect: {Exqlite.Sqlite3, :execute, ["PRAGMA foreign_keys = ON"]}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :stock_plan, StockPlanWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hBKgxpWoWy7ICBPp24LOc01W562ATaU6w7MR9JnqsP4QwrEzzXGpZimtevan1r7I",
  server: false

# Isolate the user profile path from the real home directory so the router's
# check_profile plug is deterministic in a clean environment (e.g. CI, where no
# ~/.stock_plan/profile.json exists). The file is created in test/test_helper.exs.
config :stock_plan, :profile_path, Path.expand("../tmp/test_profile.json", __DIR__)

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
