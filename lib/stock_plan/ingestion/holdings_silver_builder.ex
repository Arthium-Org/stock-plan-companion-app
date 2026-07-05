defmodule StockPlan.Ingestion.HoldingsSilverBuilder do
  @moduledoc """
  Builds Holdings Silver from Holdings Bronze.
  Creates stock_plan_holdings rows — one per vest period (RSU) or purchase lot (ESPP).
  Independent of BH Silver. Sole source for Portfolio page.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Ingestion, Holding, BronzeRaw}
  alias StockPlan.Ingestion.ValueNormalizer, as: VN
  alias StockPlan.ID
  import Ecto.Query

  require Logger

  @spec build(String.t()) :: {:ok, map()} | {:error, atom()}
  def build(account_id) do
    case find_holdings_ingestion(account_id) do
      nil ->
        {:error, :no_holdings}

      ing ->
        delete_holdings(account_id)
        rows = load_bronze(ing.ingestion_id)
        grouped = Enum.group_by(rows, & &1.sheet_name)

        rsu_count = process_rsu(account_id, ing.ingestion_id, grouped["Holdings_RSU"] || [])
        espp_count = process_espp(account_id, ing.ingestion_id, grouped["Holdings_ESPP"] || [])

        fx_count = enrich_fx(account_id)

        {:ok,
         %{
           rsu_rows: rsu_count,
           espp_rows: espp_count,
           fx_enriched: fx_count
         }}
    end
  end

  # --- Helpers ---

  defp find_holdings_ingestion(account_id) do
    Repo.one(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "HOLDINGS",
        limit: 1
    )
  end

  defp delete_holdings(account_id) do
    Repo.delete_all(from h in Holding, where: h.account_id == ^account_id)
  end

  defp load_bronze(ingestion_id) do
    Repo.all(
      from b in BronzeRaw,
        where: b.ingestion_id == ^ingestion_id,
        order_by: [asc: b.row_index]
    )
  end

  # --- RSU Processing ---

  defp process_rsu(account_id, ingestion_id, rows) do
    by_grant =
      rows
      |> Enum.map(fn row -> {row, Jason.decode!(row.raw_row_json)} end)
      |> Enum.group_by(fn {_row, data} -> data["Grant Number"] end)

    Enum.reduce(by_grant, 0, fn {grant_number, row_pairs}, total ->
      grant_data = extract_grant_data(row_pairs)

      # Build Vest Period → Sellable Shares data map
      sellable_map = build_sellable_map(row_pairs)

      # Build Vest Period → Vest Schedule data
      vest_schedule_rows =
        Enum.filter(row_pairs, fn {row, _} -> row.record_type == "Vest Schedule" end)

      count =
        Enum.reduce(vest_schedule_rows, 0, fn {_row, data}, count ->
          period = to_string(data["Vest Period"])
          vest_date = VN.parse_date(data["Vest Date"])

          if vest_date == nil do
            count
          else
            vested_qty = VN.clean_number_keep_zero(data["Vested Qty._2"])
            released_qty = VN.clean_number_keep_zero(data["Released Qty"])
            vest_qty_period = VN.clean_number(data["Granted Qty._2"])

            # Determine status
            is_vested = released_qty != nil and released_qty != "0"

            # Merge Sellable Shares data if available
            sellable = Map.get(sellable_map, period, nil)

            {sellable_qty, blocked_qty, cost_basis, metadata} =
              if sellable do
                sq = add_quantities(sellable["sellable_qty"], sellable["blocked_qty"])

                {sq, sellable["blocked_qty"], sellable["cost_basis"],
                 Jason.encode!(%{
                   "blocked" => sellable["blocked"],
                   "blocked_type" => sellable["blocked_type"],
                   "release_date" => sellable["release_date"]
                 })}
              else
                # No Sellable Shares row
                if is_vested do
                  # Vested but no Sellable Shares → fully sold
                  {"0", nil, nil, nil}
                else
                  # Unvested
                  {nil, nil, nil, nil}
                end
              end

            attrs = %{
              id: ID.generate(),
              ingestion_id: ingestion_id,
              account_id: account_id,
              symbol: grant_data.symbol,
              plan_type: "RSU",
              grant_number: grant_number,
              grant_date: grant_data.grant_date,
              granted_qty: grant_data.granted_qty,
              vest_date: vest_date,
              vest_period: parse_int(period),
              vested_qty: if(is_vested, do: vested_qty, else: vest_qty_period),
              released_qty: released_qty,
              sellable_qty: sellable_qty,
              blocked_qty: blocked_qty,
              cost_basis: cost_basis,
              purchase_price: nil,
              status: if(is_vested, do: "VESTED", else: "UNVESTED"),
              metadata_json: metadata
            }

            %Holding{} |> Holding.changeset(attrs) |> Repo.insert!()
            count + 1
          end
        end)

      total + count
    end)
  end

  defp extract_grant_data(row_pairs) do
    grant_pair = Enum.find(row_pairs, fn {row, _} -> row.record_type == "Grant" end)

    case grant_pair do
      nil ->
        %{symbol: nil, grant_date: nil, granted_qty: nil}

      {_row, data} ->
        %{
          symbol: data["Symbol"],
          grant_date: VN.parse_date(data["Grant Date"]),
          granted_qty: VN.clean_number(data["Granted Qty."])
        }
    end
  end

  defp build_sellable_map(row_pairs) do
    row_pairs
    |> Enum.filter(fn {row, _} -> row.record_type == "Sellable Shares" end)
    |> Enum.reduce(%{}, fn {_row, data}, acc ->
      period = to_string(data["Vest Period"])

      Map.put(acc, period, %{
        "sellable_qty" => VN.clean_number_keep_zero(data["Sellable Qty._3"]),
        "blocked_qty" => VN.clean_number_keep_zero(data["Blocked Share Qty."]),
        "cost_basis" => VN.clean_number(data["Est. Cost Basis (per share):"]),
        "blocked" => data["Blocked"],
        "blocked_type" => data["Blocked Type"],
        "release_date" => data["Release Date"]
      })
    end)
  end

  # --- ESPP Processing ---

  defp process_espp(account_id, ingestion_id, rows) do
    rows
    |> Enum.filter(&(&1.record_type == "Purchase"))
    |> Enum.reduce(0, fn row, count ->
      data = Jason.decode!(row.raw_row_json)

      grant_date = VN.parse_date(data["Grant Date"])
      purchase_date = VN.parse_date(data["Purchase Date"])
      symbol = data["Symbol"]

      # Cost basis = Purchase Date FMV (for Indian capital gains)
      cost_basis = VN.clean_number(data["Purchase Date FMV"])
      # Purchase price = discounted buy price (informational)
      purchase_price = VN.clean_number(data["Purchase Price"])

      # Grant Date FMV = lock-in price (strip $ prefix)
      grant_fmv = VN.clean_number(data["Grant Date FMV"])

      # ESPP: Sellable Qty IS the total owned count (not additive with Blocked)
      # Blocked Qty is a subset of Sellable Qty that's under trading restriction
      sellable_qty = VN.clean_number_keep_zero(data["Sellable Qty."])
      blocked_qty = VN.clean_number_keep_zero(data["Blocked Qty."])

      purchased_qty = VN.clean_number(data["Purchased Qty."])
      net_shares = VN.clean_number(data["Net Shares"])

      # Generate ESPP grant_number (same logic as BH Silver)
      espp_grant_number =
        if symbol && grant_date do
          hash_input = "ESPP:#{symbol}:#{Date.to_iso8601(grant_date)}"
          :crypto.hash(:sha256, hash_input) |> Base.encode16(case: :lower) |> String.slice(0, 16)
        end

      metadata =
        Jason.encode!(%{
          "discount_percent" => data["Discount Percent"],
          "grant_date_fmv" => data["Grant Date FMV"],
          "blocked" => data["Blocked"],
          "blocked_qty" => data["Blocked Qty."],
          "blocked_type" => data["Blocked Type"]
        })

      attrs = %{
        id: ID.generate(),
        ingestion_id: ingestion_id,
        account_id: account_id,
        symbol: symbol,
        plan_type: "ESPP",
        grant_number: espp_grant_number,
        grant_date: grant_date,
        granted_qty: nil,
        vest_date: purchase_date,
        vest_period: nil,
        vested_qty: purchased_qty,
        released_qty: net_shares,
        sellable_qty: sellable_qty,
        blocked_qty: blocked_qty,
        cost_basis: cost_basis,
        purchase_price: purchase_price,
        grant_fmv: grant_fmv,
        status: "VESTED",
        metadata_json: metadata
      }

      %Holding{} |> Holding.changeset(attrs) |> Repo.insert!()
      count + 1
    end)
  end

  # --- FX Enrichment ---

  defp enrich_fx(account_id) do
    holdings =
      Repo.all(
        from h in Holding,
          where:
            h.account_id == ^account_id and is_nil(h.vest_fx_rate) and not is_nil(h.vest_date)
      )

    Enum.reduce(holdings, 0, fn holding, count ->
      case StockPlan.FX.get_rate_string(holding.vest_date) do
        nil ->
          count

        rate ->
          holding |> Holding.changeset(%{vest_fx_rate: rate}) |> Repo.update!()
          count + 1
      end
    end)
  end

  # --- Utilities ---

  defp add_quantities(nil, nil), do: nil
  defp add_quantities(nil, b), do: b
  defp add_quantities(a, nil), do: a

  defp add_quantities(a, b) do
    da = if is_binary(a), do: Decimal.new(a), else: Decimal.new(to_string(a))
    db = if is_binary(b), do: Decimal.new(b), else: Decimal.new(to_string(b))
    Decimal.add(da, db) |> Decimal.to_string()
  end

  defp parse_int(nil), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(n) when is_integer(n), do: n
end
