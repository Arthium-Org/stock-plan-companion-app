defmodule StockPlan.Ingestion.BronzeRow do
  defstruct [
    :sheet_name,
    :record_type,
    :row_index,
    :parent_index,
    :raw_row_json,
    :row_hash
  ]

  @type t :: %__MODULE__{
          sheet_name: String.t(),
          record_type: String.t(),
          row_index: non_neg_integer(),
          parent_index: non_neg_integer() | nil,
          raw_row_json: String.t(),
          row_hash: String.t()
        }
end
