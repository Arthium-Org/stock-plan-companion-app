defmodule StockPlan.ManualTest.Result do
  @moduledoc false

  defstruct [:section, :status, :summary, :details, :failures]

  @type t :: %__MODULE__{
          section: String.t(),
          status: :pass | :fail,
          summary: String.t(),
          details: [String.t()],
          failures: [String.t()]
        }

  @spec pass(String.t(), String.t(), [String.t()]) :: t()
  def pass(section, summary, details \\ []) do
    %__MODULE__{section: section, status: :pass, summary: summary, details: details, failures: []}
  end

  @spec fail(String.t(), String.t(), [String.t()], [String.t()]) :: t()
  def fail(section, summary, failures, details \\ []) do
    %__MODULE__{
      section: section,
      status: :fail,
      summary: summary,
      details: details,
      failures: failures
    }
  end

  @spec all_pass?([t()]) :: boolean()
  def all_pass?(results), do: Enum.all?(results, &(&1.status == :pass))
end
