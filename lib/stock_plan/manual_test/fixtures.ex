defmodule StockPlan.ManualTest.Fixtures do
  @moduledoc """
  Reference XLSX paths for manual verification scenarios.
  Each user maps to the golden files a human would eyeball in E*Trade exports.
  """

  @users %{
    1 => %{
      label: "Sample User 1",
      dir: "test/fixtures/sample-data/su1",
      holdings: nil,
      gl: [
        "Sample-G&L_Expanded_2023.xlsx",
        "Sample-G&L_Expanded_2024.xlsx",
        "Sample-G&L_Expanded_2025.xlsx"
      ],
      capital_gains_fys: [2025, 2024, 2023]
    },
    2 => %{
      label: "Sample User 2",
      dir: "test/fixtures/sample-data/su2",
      holdings: "Sample2-ByBenefitType_expanded.xlsx",
      gl: [
        "G&L_Expanded_2025.xlsx",
        "G&L_Expanded_2026.xlsx"
      ],
      capital_gains_fys: [2026, 2025]
    },
    3 => %{
      label: "Sample User 3",
      dir: "test/fixtures/sample-data/su3",
      holdings: "Sample3-ByBenefitType_expanded.xlsx",
      gl: ["Sample3-G&L_Expanded_2025.xlsx", "Sample3-G&L_Expanded_2026.xlsx"],
      capital_gains_fys: [2026, 2025]
    },
    5 => %{
      label: "Sample User 5",
      dir: "test/fixtures/sample-data/su5",
      holdings: "SampleUser5-ByBenefitType_expanded-CRM.xlsx",
      gl: ["SampleUser5-G&L_Expanded.xlsx"],
      capital_gains_fys: [2025]
    },
    6 => %{
      label: "Sample User 1 (unsold holdings)",
      dir: "test/fixtures/sample-data/su1-unsold",
      holdings: "Holdings-ByBenefitType_expanded.xlsx",
      gl: [],
      capital_gains_fys: []
    },
    7 => %{
      label: "Sample User 5 (ADBE multi-symbol, unsold holdings)",
      dir: "test/fixtures/sample-data/su5-adbe-unsold",
      holdings: "Holdings-ADBE-ByBenefitType_expanded.xlsx",
      gl: [],
      capital_gains_fys: []
    }
  }

  @type user_id :: pos_integer()
  @type t :: %{
          label: String.t(),
          dir: String.t(),
          holdings_path: String.t(),
          gl_paths: [String.t()],
          capital_gains_fys: [pos_integer()]
        }

  @spec users() :: [user_id()]
  def users, do: Map.keys(@users) |> Enum.sort()

  @spec fetch!(user_id()) :: t()
  def fetch!(user_id) do
    case Map.get(@users, user_id) do
      nil ->
        raise ArgumentError,
              "unknown manual-test user #{user_id}. Known users: #{inspect(users())}"

      cfg ->
        dir = cfg.dir

        holdings_path =
          if cfg.holdings, do: Path.join(dir, cfg.holdings), else: nil

        %{
          label: cfg.label,
          dir: dir,
          holdings_path: holdings_path,
          gl_paths: Enum.map(cfg.gl, &Path.join(dir, &1)),
          capital_gains_fys: cfg.capital_gains_fys
        }
    end
  end
end
