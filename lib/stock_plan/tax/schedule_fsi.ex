defmodule StockPlan.Tax.ScheduleFSI do
  @moduledoc """
  Schedule FSI (Foreign Source Income) for Indian ITR.
  Thin wrapper over CapitalGains — declares foreign source income by head.
  """

  alias StockPlan.Tax.CapitalGains

  @doc """
  Build Schedule FSI for a Financial Year.
  Returns a map with country info, income heads, and FY label.
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
          # FSI only accepts positive income — losses reported separately in Schedule CG
          income_inr:
            Decimal.max(Decimal.add(cg_summary.stcg_inr, cg_summary.ltcg_inr), Decimal.new(0)),
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
      fy_label:
        "FY #{fy_start_year}-#{rem(fy_start_year + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
    }
  end
end
