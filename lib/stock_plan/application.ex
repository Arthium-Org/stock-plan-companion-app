defmodule StockPlan.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StockPlanWeb.Telemetry,
      StockPlan.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:stock_plan, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:stock_plan, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StockPlan.PubSub},
      # Start a worker by calling: StockPlan.Worker.start_link(arg)
      # {StockPlan.Worker, arg},
      # Start to serve requests, typically the last entry
      StockPlanWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StockPlan.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Seed FX rates from the bundled JSON, then best-effort refresh from the
    # configured GitHub raw URL. Both are idempotent upserts — safe to run
    # every boot; the remote fetch silently no-ops on any failure (FX-03).
    Task.start(fn -> seed_fx_if_empty() end)

    Task.start(fn ->
      StockPlan.FX.Sync.fetch_remote(Application.get_env(:stock_plan, :fx_source_url))
    end)

    # REL-02: best-effort, unauthenticated check against the public GitHub
    # Releases API for a newer app version. Async/non-blocking (D-06);
    # never raises, so an offline/404/rate-limited boot completes as a
    # silent no-op (D-08) — see StockPlan.Updates.check_async/1.
    Task.start(fn ->
      StockPlan.Updates.check_async(Application.get_env(:stock_plan, :update_check_repo_slug))
    end)

    # M22: backfill dominant_symbol on legacy ACTIVE BH/Holdings rows
    Task.start(fn -> backfill_dominant_symbol() end)

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StockPlanWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Run the FX seed every boot. The seed uses on_conflict upsert keyed on
  # (year_month, currency_pair), so re-running is idempotent: existing rows
  # stay, new months added in newer builds get inserted. This lets us ship
  # monthly FX updates with a new release without a manual reset for
  # existing installs.
  defp seed_fx_if_empty do
    StockPlan.FX.Sync.seed_from_bundle()
  rescue
    _ -> :ok
  end

  # M22: One-shot backfill — scan Bronze rows for legacy ACTIVE BH/Holdings
  # rows whose dominant_symbol is null and populate from row data.
  defp backfill_dominant_symbol do
    import Ecto.Query
    alias StockPlan.{Repo, Ingestions}
    alias StockPlan.Schema.{Ingestion, BronzeRaw}

    targets =
      Repo.all(
        from i in Ingestion,
          where:
            i.status == "ACTIVE" and is_nil(i.dominant_symbol) and
              i.category in ["BENEFIT_HISTORY", "HOLDINGS"]
      )

    Enum.each(targets, fn ing ->
      rows =
        Repo.all(
          from r in BronzeRaw,
            where: r.ingestion_id == ^ing.ingestion_id,
            select: %{raw_row_json: r.raw_row_json}
        )

      case Ingestions.extract_file_symbol(rows) do
        {:ok, symbol} ->
          ing
          |> Ecto.Changeset.change(dominant_symbol: symbol)
          |> Repo.update()

        _ ->
          :ok
      end
    end)
  rescue
    _ -> :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
