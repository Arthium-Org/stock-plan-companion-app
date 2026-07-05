defmodule StockPlan.Ingestions do
  @moduledoc """
  Ingestion Orchestrator — single entry point for all ingestion operations.
  Sequences: parse → create ingestion → write Bronze → rebuild Silver.

  Multi-symbol model (M22): BH and Holdings ingestions are scoped per-symbol.
  Each ACTIVE ingestion has a `dominant_symbol`; archiving and lookups are
  per-symbol. G&L spans all symbols and remains unscoped.
  """

  alias StockPlan.Repo

  alias StockPlan.Schema.{
    BronzeRaw,
    Exercise,
    Holding,
    Ingestion,
    Origin,
    Sale,
    SaleAllocation,
    Tranche
  }

  alias StockPlan.Ingestion.{
    XlsxParser,
    GlParser,
    HoldingsParser,
    BronzeWriter,
    SilverBuilder,
    HoldingsSilverBuilder
  }

  alias StockPlan.ID
  import Ecto.Query

  @doc """
  Ingest a Benefit History XLSX file. Extracts symbol from row data,
  archives previous BH for THAT symbol only, runs full pipeline.
  """
  def ingest_benefit_history(account_id, file_path) do
    with :ok <- validate_file(file_path),
         {:ok, file_hash} <- compute_hash(file_path),
         :ok <- check_duplicate(account_id, file_hash),
         {:ok, rows, parse_warnings} <- XlsxParser.parse(file_path),
         {:ok, symbol} <- extract_file_symbol(rows) do
      Repo.transaction(fn ->
        archive_previous_bh(account_id, symbol)

        {:ok, ing} =
          create_ingestion(account_id, file_path, file_hash, "BENEFIT_HISTORY", symbol)

        {:ok, bronze_counts} = BronzeWriter.write(ing.ingestion_id, rows)
        {:ok, silver_summary} = SilverBuilder.build(account_id)

        snapshot_json = compute_bh_snapshot(ing.ingestion_id)
        Repo.update!(Ingestion.changeset(ing, %{bh_snapshot_json: snapshot_json}))

        %{
          ingestion_id: ing.ingestion_id,
          dominant_symbol: symbol,
          bronze: bronze_counts,
          silver: silver_summary,
          parse_warnings: parse_warnings
        }
      end)
    end
  end

  @doc """
  Ingest a G&L Expanded XLSX file. Requires ACTIVE BH to exist.
  Multiple G&L files coexist — no archiving.
  """
  def ingest_gl(account_id, file_path) do
    with :ok <- validate_file(file_path),
         {:ok, file_hash} <- compute_hash(file_path),
         :ok <- check_duplicate(account_id, file_hash),
         :ok <- validate_active_bh(account_id),
         {:ok, rows, parse_warnings} <- GlParser.parse(file_path) do
      Repo.transaction(fn ->
        {:ok, ing} = create_ingestion(account_id, file_path, file_hash, "GL_EXPANDED", nil)
        {:ok, bronze_counts} = BronzeWriter.write(ing.ingestion_id, rows)
        {:ok, silver_summary} = SilverBuilder.build(account_id)

        %{
          ingestion_id: ing.ingestion_id,
          bronze: bronze_counts,
          silver: silver_summary,
          parse_warnings: parse_warnings
        }
      end)
    end
  end

  @doc """
  Ingest a Holdings (ByBenefitType) XLSX file.
  Extracts symbol, archives previous ACTIVE Holdings for THAT symbol only.
  """
  def ingest_holdings(account_id, file_path) do
    with :ok <- validate_file(file_path),
         {:ok, file_hash} <- compute_hash(file_path),
         :ok <- check_duplicate(account_id, file_hash),
         {:ok, rows, parse_warnings} <- HoldingsParser.parse(file_path),
         {:ok, symbol} <- extract_file_symbol(rows) do
      Repo.transaction(fn ->
        archive_previous_holdings(account_id, symbol)
        {:ok, ing} = create_ingestion(account_id, file_path, file_hash, "HOLDINGS", symbol)
        {:ok, bronze_counts} = BronzeWriter.write(ing.ingestion_id, rows)
        {:ok, holdings_summary} = HoldingsSilverBuilder.build(account_id)

        %{
          ingestion_id: ing.ingestion_id,
          dominant_symbol: symbol,
          bronze: bronze_counts,
          holdings: holdings_summary,
          parse_warnings: parse_warnings
        }
      end)
    end
  end

  @doc "Rebuild Silver from all existing Bronze data for the account."
  def rebuild(account_id) do
    SilverBuilder.build(account_id)
  end

  @doc """
  Wipes all data for the account — Bronze, Silver, Holdings, and Ingestion records.
  Runs in a transaction. Leaves the DB in a clean fresh state for the account.
  """
  @spec clear_all_data(String.t()) :: :ok | {:error, any()}
  def clear_all_data(account_id) do
    Repo.transaction(fn ->
      ingestion_ids =
        Repo.all(
          from i in Ingestion,
            where: i.account_id == ^account_id,
            select: i.ingestion_id
        )

      if ingestion_ids != [] do
        origin_ids =
          Repo.all(
            from o in Origin,
              where: o.ingestion_id in ^ingestion_ids,
              select: o.id
          )

        tranche_ids =
          Repo.all(
            from t in Tranche,
              where: t.ingestion_id in ^ingestion_ids,
              select: t.id
          )

        sale_ids =
          Repo.all(
            from s in Sale,
              where: s.account_id == ^account_id,
              select: s.id
          )

        Repo.delete_all(from a in SaleAllocation, where: a.sale_id in ^sale_ids)
        Repo.delete_all(from a in SaleAllocation, where: a.tranche_id in ^tranche_ids)
        Repo.delete_all(from s in Sale, where: s.account_id == ^account_id)
        Repo.delete_all(from e in Exercise, where: e.tranche_id in ^tranche_ids)
        Repo.delete_all(from t in Tranche, where: t.ingestion_id in ^ingestion_ids)
        Repo.delete_all(from o in Origin, where: o.id in ^origin_ids)
        Repo.delete_all(from b in BronzeRaw, where: b.ingestion_id in ^ingestion_ids)
        Repo.delete_all(from h in Holding, where: h.account_id == ^account_id)
        Repo.delete_all(from i in Ingestion, where: i.account_id == ^account_id)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Inserted_at of the most recent ingestion (any category, any status), or nil."
  def latest_upload_at(account_id) do
    Repo.one(
      from i in Ingestion,
        where: i.account_id == ^account_id,
        order_by: [desc: i.inserted_at],
        limit: 1,
        select: i.inserted_at
    )
  end

  @doc "Returns true if any ACTIVE ingestion exists for the account."
  def any_active?(account_id) do
    Repo.exists?(
      from i in Ingestion,
        where: i.account_id == ^account_id and i.status == "ACTIVE"
    )
  end

  # ============================================================
  # Per-symbol API (M22)
  # ============================================================

  @doc "ACTIVE Benefit History ingestion for {account, symbol}, or nil."
  @spec active_bh(String.t(), String.t()) :: Ingestion.t() | nil
  def active_bh(account_id, symbol) do
    Repo.one(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY" and i.dominant_symbol == ^symbol,
        limit: 1
    )
  end

  @doc "ACTIVE Holdings ingestion for {account, symbol}, or nil."
  @spec active_holdings(String.t(), String.t()) :: Ingestion.t() | nil
  def active_holdings(account_id, symbol) do
    Repo.one(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "HOLDINGS" and i.dominant_symbol == ^symbol,
        limit: 1
    )
  end

  @doc "Distinct symbols with at least one ACTIVE BH ingestion."
  @spec active_bh_symbols(String.t()) :: [String.t()]
  def active_bh_symbols(account_id) do
    Repo.all(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY" and not is_nil(i.dominant_symbol),
        distinct: true,
        select: i.dominant_symbol,
        order_by: i.dominant_symbol
    )
  end

  @doc "Distinct symbols with at least one ACTIVE Holdings ingestion."
  @spec active_holdings_symbols(String.t()) :: [String.t()]
  def active_holdings_symbols(account_id) do
    Repo.all(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "HOLDINGS" and not is_nil(i.dominant_symbol),
        distinct: true,
        select: i.dominant_symbol,
        order_by: i.dominant_symbol
    )
  end

  @doc "True if any ACTIVE BH ingestion exists (any symbol)."
  @spec any_active_bh?(String.t()) :: boolean()
  def any_active_bh?(account_id) do
    Repo.exists?(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY"
    )
  end

  @doc """
  True if any ACTIVE BH ingestion's snapshot indicates current shares exist —
  either vested-unsold origins or unvested tranches. Returns false when no
  snapshot is present (legacy BH or no BH).
  """
  @spec bh_has_current_shares?(String.t()) :: boolean()
  def bh_has_current_shares?(account_id) do
    Repo.exists?(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and
            i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY" and
            not is_nil(i.bh_snapshot_json) and
            (fragment("json_extract(?, '$.vested_unsold_origin_count')", i.bh_snapshot_json) > 0 or
               fragment("json_extract(?, '$.unvested_count')", i.bh_snapshot_json) > 0)
    )
  end

  @doc "True if any ACTIVE Holdings ingestion exists for the account."
  @spec has_active_holdings?(String.t()) :: boolean()
  def has_active_holdings?(account_id) do
    Repo.exists?(
      from i in Ingestion,
        where: i.account_id == ^account_id and i.status == "ACTIVE" and i.category == "HOLDINGS"
    )
  end

  @doc """
  Extract the symbol from parsed BH/Holdings rows.
  Looks at the `Symbol` field inside `raw_row_json`. Returns the most
  frequent non-empty symbol (defensive against future multi-symbol files).
  """
  @spec extract_file_symbol([map()]) :: {:ok, String.t()} | {:error, :no_symbol}
  def extract_file_symbol(rows) when is_list(rows) do
    counts =
      rows
      |> Enum.map(&row_symbol/1)
      |> Enum.reject(&(&1 == nil or &1 == ""))
      |> Enum.frequencies()

    case Enum.max_by(counts, fn {_sym, count} -> count end, fn -> nil end) do
      nil -> {:error, :no_symbol}
      {symbol, _count} -> {:ok, symbol}
    end
  end

  defp row_symbol(%{raw_row_json: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = data} -> Map.get(data, "Symbol")
      _ -> nil
    end
  end

  defp row_symbol(_), do: nil

  # --- Helpers ---

  defp validate_file(path) do
    if File.exists?(path), do: :ok, else: {:error, :file_not_found}
  end

  defp compute_hash(path) do
    hash =
      File.stream!(path, 2048)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  end

  defp check_duplicate(account_id, file_hash) do
    case Repo.one(
           from i in Ingestion,
             where: i.account_id == ^account_id and i.file_hash == ^file_hash,
             limit: 1
         ) do
      nil -> :ok
      existing -> {:error, :duplicate_file, existing.ingestion_id}
    end
  end

  defp archive_previous_bh(account_id, symbol) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY" and i.dominant_symbol == ^symbol
      ),
      set: [status: "ARCHIVED", updated_at: now]
    )
  end

  defp archive_previous_holdings(account_id, symbol) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and
            i.category == "HOLDINGS" and i.dominant_symbol == ^symbol
      ),
      set: [status: "ARCHIVED", updated_at: now]
    )
  end

  defp validate_active_bh(account_id) do
    if any_active_bh?(account_id), do: :ok, else: {:error, :no_benefit_history}
  end

  defp compute_bh_snapshot(ingestion_id) do
    vested_tranches =
      Repo.all(
        from t in Tranche,
          where: t.ingestion_id == ^ingestion_id and t.status == "VESTED",
          select: {t.origin_id, t.net_quantity}
      )

    vested_by_origin =
      vested_tranches
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {origin_id, qtys} ->
        total =
          Enum.reduce(qtys, Decimal.new(0), fn
            nil, acc -> acc
            qty, acc -> Decimal.add(acc, qty)
          end)

        {origin_id, total}
      end)

    sales =
      Repo.all(
        from s in Sale,
          where: s.ingestion_id == ^ingestion_id,
          select: {s.origin_id, s.sale_date, s.total_quantity}
      )

    sold_by_origin =
      sales
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 2))
      |> Map.new(fn {origin_id, qtys} ->
        total =
          Enum.reduce(qtys, Decimal.new(0), fn
            nil, acc -> acc
            qty, acc -> Decimal.add(acc, qty)
          end)

        {origin_id, total}
      end)

    vested_unsold_origin_count =
      Enum.count(vested_by_origin, fn {origin_id, vested_qty} ->
        sold_qty = Map.get(sold_by_origin, origin_id, Decimal.new(0))
        Decimal.gt?(vested_qty, sold_qty)
      end)

    unvested_count =
      Repo.one(
        from t in Tranche,
          where: t.ingestion_id == ^ingestion_id and t.status == "UNVESTED",
          select: count()
      ) || 0

    sale_years =
      sales
      |> Enum.map(fn {_, sale_date, _} -> sale_date.year end)
      |> Enum.uniq()
      |> Enum.sort()

    Jason.encode!(%{
      vested_unsold_origin_count: vested_unsold_origin_count,
      unvested_count: unvested_count,
      sale_years: sale_years
    })
  end

  defp create_ingestion(account_id, file_path, file_hash, category, dominant_symbol) do
    %Ingestion{}
    |> Ingestion.changeset(%{
      ingestion_id: ID.generate(),
      account_id: account_id,
      broker: "ETRADE",
      source_type: "XLSX",
      file_name: Path.basename(file_path),
      file_hash: file_hash,
      status: "ACTIVE",
      category: category,
      dominant_symbol: dominant_symbol
    })
    |> Repo.insert()
  end
end
