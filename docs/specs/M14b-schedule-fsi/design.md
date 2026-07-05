# Design: M14b — Schedule FSI

## Architecture

```
CapitalGains.build(account_id, fy_start)
  → {rows, summary}  (already exists from M14)
  → summary.stcg_inr, summary.ltcg_inr

ScheduleFSI.build(account_id, fy_start)
  → FSI row with CG breakdown
  → All other heads = 0 or "User to populate"
```

Schedule FSI is a thin wrapper over existing Capital Gains data. No new queries needed.

## Context Module

```elixir
defmodule StockPlan.Tax.ScheduleFSI do
  @doc """
  Build Schedule FSI for a Financial Year.
  Returns a map with all income heads for USA.
  """
  def build(account_id, fy_start_year) do
    {_rows, cg_summary} = CapitalGains.build(account_id, fy_start_year)

    %{
      country: "United States of America",
      country_code: "002",
      tin_placeholder: "Your TIN in USA (if available) or Passport Number",

      heads: [
        %{
          sl_no: "i",
          head: "Salary",
          income_inr: nil,
          tax_paid_outside_inr: nil,
          tax_payable_india: nil,
          tax_relief: nil,
          dtaa_article: nil,
          note: "Not applicable — RSU/ESPP perquisite is Indian salary income"
        },
        %{
          sl_no: "ii",
          head: "House Property",
          income_inr: nil,
          tax_paid_outside_inr: nil,
          tax_payable_india: nil,
          tax_relief: nil,
          dtaa_article: nil,
          note: nil
        },
        %{
          sl_no: "iii",
          head: "Capital Gains",
          income_inr: Decimal.add(cg_summary.stcg_inr, cg_summary.ltcg_inr),
          income_detail: %{
            stcg_usd: cg_summary.stcg_usd,
            stcg_inr: cg_summary.stcg_inr,
            ltcg_usd: cg_summary.ltcg_usd,
            ltcg_inr: cg_summary.ltcg_inr
          },
          tax_paid_outside_inr: Decimal.new(0),
          tax_payable_india: :user_to_populate,
          tax_relief: "Not applicable for CG as no withholding",
          dtaa_article: "Nil",
          note: nil
        },
        %{
          sl_no: "iv",
          head: "Other Sources (Dividends)",
          income_inr: Decimal.new(0),
          tax_paid_outside_inr: Decimal.new(0),
          tax_payable_india: :user_to_populate,
          tax_relief: :user_to_populate,
          dtaa_article: :user_to_populate,
          note: "Dividend tracking not yet available"
        }
      ],

      fy_label: "FY #{fy_start_year}-#{rem(fy_start_year + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
    }
  end

  def to_csv(fsi_data) do
    header = "Sl No,Country Code,TIN,Head of Income,Income (INR),Tax Paid Outside India (INR),Tax Payable in India (INR),Tax Relief (INR),DTAA Article\r\n"

    rows =
      fsi_data.heads
      |> Enum.map(fn head ->
        [
          head.sl_no,
          fsi_data.country_code,
          fsi_data.tin_placeholder,
          head.head,
          format_value(head.income_inr),
          format_value(head.tax_paid_outside_inr),
          format_user_field(head.tax_payable_india),
          format_user_field(head.tax_relief),
          format_user_field(head.dtaa_article)
        ]
        |> Enum.map(&csv_safe/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\r\n")

    header <> rows
  end

  defp format_value(nil), do: ""
  defp format_value(%Decimal{} = d), do: Decimal.round(d, 0) |> Decimal.to_string()
  defp format_value(v), do: to_string(v)

  defp format_user_field(:user_to_populate), do: "User to populate"
  defp format_user_field(nil), do: ""
  defp format_user_field(v), do: to_string(v)

  defp csv_safe(value) when is_binary(value) do
    String.replace(value, ",", ";")
  end
  defp csv_safe(value), do: to_string(value)
end
```

## UI — Tax Centre Third Tab

```
┌──────────────────────────────────────────────────┐
│  Tax Centre                                       │
│                                                   │
│  ┃ Schedule FA ┃  Capital Gains ┃  Schedule FSI   │
│                                                   │
│  FY: [2025-26 ▼]                  [Download CSV]  │
│                                                   │
│  Country: United States of America (002)           │
│  TIN: [User to enter]                              │
│                                                   │
│  ┌──────────────────────────────────────────────┐ │
│  │ # │ Head of Income  │ Income  │ Tax Paid │...│ │
│  │ i │ Salary          │   —     │    —     │   │ │
│  │ ii│ House Property   │   —     │    —     │   │ │
│  │iii│ Capital Gains    │ ₹7,530  │   ₹0    │   │ │
│  │   │  STCG: ₹7,530   │         │         │   │ │
│  │   │  LTCG: ₹0       │         │         │   │ │
│  │ iv│ Other Sources    │   ₹0    │   ₹0    │   │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  Note: "Tax payable in India" depends on your     │
│  effective tax rate. Consult your tax advisor.     │
└──────────────────────────────────────────────────┘
```

## Files

- `lib/stock_plan/tax/schedule_fsi.ex` — Context module (thin wrapper)
- `lib/stock_plan_web/live/tax_centre_live.ex` — Add third tab
