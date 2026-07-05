defmodule StockPlan.StockMeta do
  @moduledoc """
  Static lookup of per-symbol metadata (legal name, address, country code)
  used by Schedule FA CSV generation and per-symbol UI labels.

  Data lives in `priv/stock_meta.json`. Loaded lazily on first call and
  cached via `:persistent_term`. Add new symbols by editing the JSON file
  and shipping a new release.
  """

  @persistent_key {__MODULE__, :meta}
  @file_name "stock_meta.json"

  defmodule UnknownSymbolError do
    defexception [:symbol]
    @impl true
    def message(%{symbol: s}),
      do: "Unknown stock symbol: #{inspect(s)}. Add to priv/#{"stock_meta.json"}."
  end

  @doc "Lookup metadata for a symbol. Returns {:ok, map} or {:error, :unknown_symbol}."
  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_symbol}
  def get(symbol) when is_binary(symbol) do
    case Map.fetch(all(), symbol) do
      {:ok, meta} -> {:ok, meta}
      :error -> {:error, :unknown_symbol}
    end
  end

  @doc "Bang variant of get/1. Raises UnknownSymbolError on unknown symbol."
  @spec get!(String.t()) :: map()
  def get!(symbol) when is_binary(symbol) do
    case get(symbol) do
      {:ok, meta} -> meta
      {:error, :unknown_symbol} -> raise UnknownSymbolError, symbol: symbol
    end
  end

  @doc "Full map of all known symbols."
  @spec all() :: %{String.t() => map()}
  def all do
    case :persistent_term.get(@persistent_key, :undefined) do
      :undefined ->
        meta = load_from_disk()
        :persistent_term.put(@persistent_key, meta)
        meta

      meta ->
        meta
    end
  end

  @doc "Returns true iff the symbol has metadata."
  @spec known?(String.t()) :: boolean()
  def known?(symbol) when is_binary(symbol), do: Map.has_key?(all(), symbol)

  @doc false
  def __clear_cache__, do: :persistent_term.erase(@persistent_key)

  defp load_from_disk do
    path = Path.join(:code.priv_dir(:stock_plan), @file_name)
    body = File.read!(path)
    Jason.decode!(body)
  end
end
