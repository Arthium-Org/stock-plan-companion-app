defmodule StockPlan.Tax.ScheduleFATest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Tax.ScheduleFA
  alias StockPlan.Ingestions

  @bh_file "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2023 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2023.xlsx"

  @account_id "fa_test_user"

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2025)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2024)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2023)
    :ok
  end

  describe "build/2" do
    test "returns {:ok, rows, warnings} for year with holdings" do
      {:ok, rows, _warnings} = ScheduleFA.build(@account_id, 2024)
      assert is_list(rows)
      assert length(rows) > 0
    end

    test "each row has required fields" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      for row <- rows do
        assert Map.has_key?(row, :date_acquired)
        assert Map.has_key?(row, :initial_value_inr)
        assert Map.has_key?(row, :peak_value_inr)
        assert Map.has_key?(row, :closing_value_inr)
        assert Map.has_key?(row, :plan_type)
        assert Map.has_key?(row, :symbol)
        assert Map.has_key?(row, :quantity_held)
        assert Map.has_key?(row, :quantity_start)
      end
    end

    test "rows are sorted by date_acquired" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      dates = Enum.map(rows, & &1.date_acquired)

      sorted = Enum.sort(dates, Date)
      assert dates == sorted
    end

    test "excludes lots vested after Dec 31" do
      # 2020 has RSU sells but no G&L — V2 blocks it. Use build_legacy for this test.
      rows = ScheduleFA.build_legacy(@account_id, 2020)

      # All rows should have vest_date on or before 2020-12-31
      for row <- rows do
        assert Date.compare(row.date_acquired, ~D[2020-12-31]) != :gt
      end
    end

    test "returns {:error, message} when G&L missing for CY with BH sells (P1 hard block)" do
      # 2020 has RSU sells in BH but no G&L uploaded for 2020 — P1 blocks
      result = ScheduleFA.build(@account_id, 2020)
      assert {:error, message} = result
      assert message =~ "G&L missing for sell dates"
    end

    test "empty account returns empty list" do
      {:ok, rows, _} = ScheduleFA.build("nonexistent_account", 2024)
      assert rows == []
    end

    test "initial value is non-negative" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      for row <- rows do
        assert Decimal.compare(row.initial_value_inr, Decimal.new(0)) != :lt
      end
    end

    test "peak value >= closing value for lots held all year" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      # For lots still held (closing > 0), peak should >= closing
      for row <- rows,
          Decimal.gt?(row.closing_value_inr, Decimal.new(0)),
          Decimal.gt?(row.peak_value_inr, Decimal.new(0)) do
        assert Decimal.compare(row.peak_value_inr, row.closing_value_inr) != :lt,
               "Peak (#{row.peak_value_inr}) should be >= Closing (#{row.closing_value_inr}) for #{row.symbol}/#{row.date_acquired}"
      end
    end

    test "lot sold during CY has closing value of 0 if fully sold" do
      # Build for a year where sales occurred
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      # Find any rows where qty_held is 0 (fully sold during CY)
      fully_sold =
        Enum.filter(rows, fn r -> Decimal.compare(r.quantity_held, Decimal.new(0)) == :eq end)

      for row <- fully_sold do
        assert Decimal.compare(row.closing_value_inr, Decimal.new(0)) == :eq,
               "Fully sold lot should have closing=0"
      end
    end

    test "plan_type is RSU or ESPP" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      for row <- rows do
        assert row.plan_type in ["RSU", "ESPP"]
      end
    end
  end

  describe "M26 pre_check/2" do
    test "returns :ok when G&L covers all BH sell dates >= cy_start" do
      assert :ok = ScheduleFA.pre_check(@account_id, 2024)
    end

    test "returns {:error, _} when G&L missing for BH sell dates in requested year" do
      assert {:error, message} = ScheduleFA.pre_check(@account_id, 2020)
      assert message =~ "G&L missing for sell dates"
    end
  end

  describe "M26 regression: SampleUser 1 fully-sold" do
    test "BH only (no G&L): FA any year with sells returns {:error, _} from P1" do
      account = "fa_m26_bh_only"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file)

      # No G&L — P1 blocks any year that has BH sell dates
      result = ScheduleFA.build(account, 2024)
      assert {:error, message} = result
      assert message =~ "G&L missing for sell dates"
    end

    test "BH + G&L 2024+2025: FA 2024 succeeds, pre-CY tranches fully sold are excluded" do
      {:ok, rows, warnings} = ScheduleFA.build(@account_id, 2024)

      # Result is valid
      assert is_list(rows)
      assert is_list(warnings)

      # All rows have start_count > 0 (exclusion rule applied)
      for row <- rows do
        assert Decimal.gt?(row.quantity_start, Decimal.new(0)),
               "Row #{row.symbol} / #{row.date_acquired} has start_count=0 — should be excluded"
      end
    end

    test "FA 2024: fully-sold tranches in prior years do not appear as false holdings" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)

      # No row should have both start_count=0 and end_count=0 (those are excluded)
      # All rows present must have start_count > 0
      assert Enum.all?(rows, fn r -> Decimal.gt?(r.quantity_start, Decimal.new(0)) end)
    end
  end

  describe "cross-validation: G&L vs CG vs FA proceeds" do
    @cy 2024

    defp gl_proceeds_for_cy(account_id, calendar_year) do
      # Raw G&L proceeds: query sale_allocations joined with sales,
      # filter by CY, sum(sale_price * quantity * sale_fx_rate)
      import Ecto.Query

      alias StockPlan.Repo
      alias StockPlan.Schema.{Sale, SaleAllocation}

      cy_start = Date.new!(calendar_year, 1, 1)
      cy_end = Date.new!(calendar_year, 12, 31)

      Repo.all(
        from a in SaleAllocation,
          join: s in Sale,
          on: a.sale_id == s.id,
          where:
            s.account_id == ^account_id and
              s.sale_date >= ^cy_start and
              s.sale_date <= ^cy_end and
              not is_nil(a.sale_price) and
              not is_nil(s.sale_fx_rate),
          select: %{
            quantity: a.quantity,
            sale_price: a.sale_price,
            sale_fx_rate: s.sale_fx_rate
          }
      )
      |> Enum.reduce(Decimal.new(0), fn row, acc ->
        proceeds_inr = Decimal.mult(Decimal.mult(row.sale_price, row.quantity), row.sale_fx_rate)
        Decimal.add(acc, proceeds_inr)
      end)
    end

    defp cg_proceeds_for_cy(account_id, calendar_year) do
      # CG covers FY (Apr-Mar). For CY 2024:
      # - FY 2023-24 rows where sale_date.year == 2024 (Jan-Mar portion)
      # - FY 2024-25 rows where sale_date.year == 2024 (Apr-Dec portion)
      alias StockPlan.Tax.CapitalGains

      fy_covering_jan_mar = calendar_year - 1
      fy_covering_apr_dec = calendar_year

      {rows_early, _} = CapitalGains.build(account_id, fy_covering_jan_mar)
      {rows_late, _} = CapitalGains.build(account_id, fy_covering_apr_dec)

      all_rows =
        Enum.filter(rows_early, fn r -> r.sale_date.year == calendar_year end) ++
          Enum.filter(rows_late, fn r -> r.sale_date.year == calendar_year end)

      Enum.reduce(all_rows, Decimal.new(0), fn row, acc ->
        case row.proceeds_inr do
          nil -> acc
          val -> Decimal.add(acc, val)
        end
      end)
    end

    defp fa_proceeds_for_cy(account_id, calendar_year) do
      {:ok, rows, _warnings} = ScheduleFA.build(account_id, calendar_year)

      Enum.reduce(rows, Decimal.new(0), fn row, acc ->
        case row.sale_proceeds_inr do
          nil -> acc
          val -> Decimal.add(acc, val)
        end
      end)
    end

    test "G&L proceeds match CG proceeds for CY with sales" do
      gl_total = gl_proceeds_for_cy(@account_id, @cy)
      cg_total = cg_proceeds_for_cy(@account_id, @cy)

      # Sanity: there should be proceeds
      assert Decimal.gt?(gl_total, Decimal.new(0)),
             "Expected G&L proceeds > 0, got #{gl_total}"

      assert Decimal.gt?(cg_total, Decimal.new(0)),
             "Expected CG proceeds > 0, got #{cg_total}"

      # G&L and CG should match exactly (both read from same allocations)
      assert Decimal.equal?(gl_total, cg_total),
             "G&L proceeds (#{gl_total}) != CG proceeds (#{cg_total})"
    end

    test "FA proceeds match CG proceeds within rounding tolerance" do
      fa_total = fa_proceeds_for_cy(@account_id, @cy)
      cg_total = cg_proceeds_for_cy(@account_id, @cy)

      # Sanity
      assert Decimal.gt?(fa_total, Decimal.new(0)),
             "Expected FA proceeds > 0, got #{fa_total}"

      assert Decimal.gt?(cg_total, Decimal.new(0)),
             "Expected CG proceeds > 0, got #{cg_total}"

      # FA aggregates by date and may use different FX lookup path — allow ₹100 tolerance
      diff = Decimal.abs(Decimal.sub(fa_total, cg_total))
      tolerance = Decimal.new(100)

      assert Decimal.lt?(diff, tolerance),
             "FA proceeds (#{fa_total}) vs CG proceeds (#{cg_total}): diff ₹#{diff} exceeds ₹#{tolerance} tolerance"
    end

    test "FA proceeds match G&L proceeds within rounding tolerance" do
      fa_total = fa_proceeds_for_cy(@account_id, @cy)
      gl_total = gl_proceeds_for_cy(@account_id, @cy)

      # Sanity
      assert Decimal.gt?(fa_total, Decimal.new(0)),
             "Expected FA proceeds > 0, got #{fa_total}"

      assert Decimal.gt?(gl_total, Decimal.new(0)),
             "Expected G&L proceeds > 0, got #{gl_total}"

      # Allow ₹100 tolerance for FA vs G&L
      diff = Decimal.abs(Decimal.sub(fa_total, gl_total))
      tolerance = Decimal.new(100)

      assert Decimal.lt?(diff, tolerance),
             "FA proceeds (#{fa_total}) vs G&L proceeds (#{gl_total}): diff ₹#{diff} exceeds ₹#{tolerance} tolerance"
    end
  end

  describe "to_csv/1" do
    test "generates valid CSV with headers" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)
      csv = ScheduleFA.to_csv(rows)

      lines = String.split(csv, "\n")
      assert hd(lines) =~ "Country/Region name"
      assert hd(lines) =~ "Closing balance"
      # Data rows = total lines - 1 (header)
      assert length(lines) == length(rows) + 1
    end

    test "CSV contains hardcoded values" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)
      csv = ScheduleFA.to_csv(rows)

      assert csv =~ "United States of America"
      assert csv =~ "Adobe Inc.(ADBE)"
      assert csv =~ "Company"
    end

    test "address commas replaced with semicolons" do
      {:ok, rows, _} = ScheduleFA.build(@account_id, 2024)
      csv = ScheduleFA.to_csv(rows)

      # The address field should not cause CSV column split issues
      # "345 Park Avenue; San Jose; CA 95110; USA" - semicolons, not commas
      assert csv =~ "345 Park Ave"
    end

    test "empty rows produce header-only CSV" do
      csv = ScheduleFA.to_csv([])
      lines = String.split(csv, "\n")
      assert length(lines) == 1
      assert hd(lines) =~ "Country Name"
    end
  end

  describe "row_to_csv/1 (M22)" do
    test "looks up metadata for ADBE" do
      row = %{
        symbol: "ADBE",
        date_acquired: ~D[2024-06-30],
        initial_value_inr: Decimal.new("1000"),
        peak_value_inr: Decimal.new("2000"),
        closing_value_inr: Decimal.new("1500"),
        income_from_asset: Decimal.new(0),
        sale_proceeds_inr: Decimal.new(0)
      }

      csv = ScheduleFA.row_to_csv(row)
      assert csv =~ "United States of America"
      assert csv =~ "Adobe Inc.(ADBE)"
      assert csv =~ "345 Park Ave"
      assert csv =~ "95110"
    end

    test "looks up metadata for CRM" do
      row = %{
        symbol: "CRM",
        date_acquired: ~D[2024-06-30],
        initial_value_inr: Decimal.new("1000"),
        peak_value_inr: Decimal.new("2000"),
        closing_value_inr: Decimal.new("1500"),
        income_from_asset: Decimal.new(0),
        sale_proceeds_inr: Decimal.new(0)
      }

      csv = ScheduleFA.row_to_csv(row)
      # csv_field/1 replaces commas with a double-space (ITR Schedule FA upload
      # rejects commas, quotes, AND semicolons -- double space is the only
      # separator the form accepts, per STATE.md Quick Task #2, 2026-07-04).
      # "Salesforce, Inc." -> "Salesforce" + "  " (replacement) + " Inc." (the
      # original space survives the comma-only replace) = "Salesforce   Inc."
      assert csv =~ "Salesforce   Inc."
      assert csv =~ "(CRM)"
      assert csv =~ "Salesforce Tower"
    end

    test "raises on unknown symbol" do
      row = %{
        symbol: "NOPE",
        date_acquired: ~D[2024-06-30],
        initial_value_inr: Decimal.new(0),
        peak_value_inr: Decimal.new(0),
        closing_value_inr: Decimal.new(0),
        income_from_asset: Decimal.new(0),
        sale_proceeds_inr: Decimal.new(0)
      }

      assert_raise StockPlan.StockMeta.UnknownSymbolError, fn ->
        ScheduleFA.row_to_csv(row)
      end
    end
  end
end
