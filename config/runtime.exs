import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/stock_plan start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :stock_plan, StockPlanWeb.Endpoint, server: true
end

config :stock_plan, StockPlanWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4002"))]

if config_env() == :prod do
  # Database path: use DATABASE_PATH env var, or default to ~/.stock_plan/stock_plan.db
  database_path =
    System.get_env("DATABASE_PATH") ||
      (fn ->
         # System.user_home() resolves the per-user home cross-platform
         # (USERPROFILE on Windows, HOME on macOS/Linux). HOME alone is unset
         # on Windows, which would drop the DB into a non-writable cwd.
         home = System.user_home() || System.get_env("HOME") || "."
         dir = Path.join(home, ".stock_plan")
         File.mkdir_p!(dir)
         Path.join(dir, "stock_plan.db")
       end).()

  config :stock_plan, StockPlan.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    after_connect: {Exqlite.Sqlite3, :execute, ["PRAGMA foreign_keys = ON"]}

  # Secret key base: use env var or a built-in default for desktop use.
  # For a local desktop app this is fine — no external network exposure.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "QG0X8KznVTn0hgAOah5U5d1B2TdEKBc26/pypy04ooK6LAjl3+FIRlPeS6jw5n6v"

  host = System.get_env("PHX_HOST") || "localhost"

  config :stock_plan, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :stock_plan, StockPlanWeb.Endpoint,
    url: [host: host, port: 4002, scheme: "http"],
    http: [ip: {127, 0, 0, 1}],
    server: true,
    secret_key_base: secret_key_base

  # Enable auto-setup (migrate + seed + open browser) in production releases
  config :stock_plan, auto_setup: true
end
