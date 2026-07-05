defmodule StockPlan.FX.Sync do
  @moduledoc """
  Loads FX monthly rates into `stock_plan_fx_monthly_rates` from two sources:

    1. The bundled `priv/fx/fx_rates.json` file, always available offline.
    2. A best-effort remote refresh from a GitHub raw URL (`:fx_source_url`
       app config), which silently no-ops on any failure — offline, 404,
       timeout, or malformed JSON — falling back to whatever is already
       seeded (FX-03).

  Both paths parse the payload as data only (`Jason.decode!/1`) and never
  evaluate it as code (D-05) — a tampered or malformed remote file can, at
  worst, fail to update rates; it can never execute arbitrary Elixir.
  """

  alias StockPlan.{Repo, ID}
  alias StockPlan.Schema.FxMonthlyRate

  @bundled_path Path.join(:code.priv_dir(:stock_plan), "fx/fx_rates.json")

  @doc """
  Seed FX rates from the bundled JSON file shipped in `priv/fx/fx_rates.json`.

  Always safe to call — reads a local file, so no network is involved.
  Rescues any error (missing file, malformed JSON) and returns `:ok`
  regardless, matching the existing boot-seed convention.
  """
  @spec seed_from_bundle() :: :ok
  def seed_from_bundle do
    @bundled_path
    |> File.read!()
    |> Jason.decode!()
    |> upsert_all()
  rescue
    _ -> :ok
  end

  @doc """
  Best-effort remote refresh from `url` (expected to be the GitHub raw
  location of `fx_rates.json`). Silently no-ops on any failure — offline,
  non-200 response, timeout, or malformed JSON — per FX-03. Never raises.
  """
  @spec fetch_remote(String.t() | nil) :: :ok
  def fetch_remote(nil), do: :ok
  def fetch_remote(""), do: :ok

  def fetch_remote(url) do
    case Req.get(url,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000,
           headers: [{"user-agent", "StockPlanManager"}]
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if valid_payload?(body), do: upsert_all(body), else: :ok

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        decoded = Jason.decode!(body)
        if valid_payload?(decoded), do: upsert_all(decoded), else: :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  # V5 input validation — reject and no-op on any shape that doesn't match
  # the expected schema rather than trusting remote structure blindly.
  defp valid_payload?(%{"schema_version" => v, "rates" => rates})
       when is_integer(v) and is_list(rates),
       do: true

  defp valid_payload?(_), do: false

  defp upsert_all(%{"rates" => rates}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    rows = Enum.map(rates, &build_row(&1, now))

    Repo.insert_all(FxMonthlyRate, rows,
      on_conflict:
        {:replace,
         [
           :rate_date,
           :tt_buying_rate_month_end,
           :standard_rate_month_end,
           :standard_rate_month_avg,
           :source,
           :updated_at
         ]},
      conflict_target: [:year_month, :currency_pair]
    )

    :ok
  end

  defp upsert_all(_), do: :ok

  defp build_row(row, now) do
    year_month = row["year_month"]
    tt_rate = row["tt_buying_rate_month_end"]
    month_end = row["standard_rate_month_end"]
    month_avg = row["standard_rate_month_avg"]

    %{
      id: ID.generate(),
      rate_date: rate_date_for(year_month),
      year_month: year_month,
      currency_pair: "USD/INR",
      tt_buying_rate_month_end: to_decimal(tt_rate),
      standard_rate_month_end: to_decimal(month_end),
      standard_rate_month_avg: to_decimal(month_avg),
      source: source_for(tt_rate, month_end, month_avg),
      inserted_at: now,
      updated_at: now
    }
  end

  # insert_all/3 with a schema module dumps values directly (no changeset
  # cast), and SafeDecimal.dump/1 only accepts nil | %Decimal{} — convert
  # the JSON's plain rate strings before building the row map.
  defp to_decimal(nil), do: nil
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  # rate_date is required on the schema but not present in the JSON —
  # derive it as the last day of the row's year_month (mirrors the retired
  # .exs seed's derivation).
  defp rate_date_for(year_month) do
    [year, month] = String.split(year_month, "-")
    Date.new!(String.to_integer(year), String.to_integer(month), 1) |> Date.end_of_month()
  end

  defp source_for(tt_rate, month_end, month_avg) do
    [
      if(tt_rate, do: "SBI_TT_BUY"),
      if(month_end, do: "RBI_MONTH_END"),
      if(month_avg, do: "X_RATES_MONTH_AVG")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" + ")
  end
end
