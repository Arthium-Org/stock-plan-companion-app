defmodule StockPlan.TestFixtures do
  alias StockPlan.Repo
  alias StockPlan.Schema.Ingestion
  alias StockPlan.ID

  def create_ingestion(attrs \\ %{}) do
    defaults = %{
      ingestion_id: ID.generate(),
      account_id: "default",
      broker: "ETRADE",
      source_type: "XLSX",
      file_name: "BenefitHistory.xlsx",
      file_hash: "sha256_" <> ID.generate(),
      status: "ACTIVE",
      category: "BENEFIT_HISTORY"
    }

    %Ingestion{}
    |> Ingestion.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_gl_ingestion(attrs \\ %{}) do
    defaults = %{
      ingestion_id: ID.generate(),
      account_id: "default",
      broker: "ETRADE",
      source_type: "XLSX",
      file_name: "G&L_Expanded.xlsx",
      file_hash: "sha256_" <> ID.generate(),
      status: "ACTIVE",
      category: "GL_EXPANDED"
    }

    %Ingestion{}
    |> Ingestion.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_holdings_ingestion(attrs \\ %{}) do
    defaults = %{
      ingestion_id: ID.generate(),
      account_id: "default",
      broker: "ETRADE",
      source_type: "XLSX",
      file_name: "ByBenefitType_expanded.xlsx",
      file_hash: "sha256_" <> ID.generate(),
      status: "ACTIVE",
      category: "HOLDINGS"
    }

    %Ingestion{}
    |> Ingestion.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
