defmodule StockPlan.Profile do
  @moduledoc """
  Single source of truth for the on-disk user profile location.

  Defaults to `~/.stock_plan/profile.json`. The path is overridable via
  `config :stock_plan, :profile_path` so tests (and any non-default deployment)
  can point it at an isolated location instead of the real home directory. This
  keeps the router's `check_profile` plug deterministic in a clean environment
  (e.g. CI), where no `~/.stock_plan/profile.json` exists.
  """

  @doc "Absolute path to the profile.json file."
  @spec path() :: String.t()
  def path do
    Application.get_env(:stock_plan, :profile_path) ||
      Path.join(System.user_home!() || ".", ".stock_plan/profile.json")
  end

  @doc "Directory containing the profile file."
  @spec dir() :: String.t()
  def dir, do: Path.dirname(path())

  @doc """
  Reads `key` from the flat JSON map stored at `path/0` and returns its
  value, or `default` if the file is missing, unreadable, or fails to
  decode as JSON. Never raises — mirrors the read-decode shape previously
  duplicated in `home_live.ex`'s `load_profile/0`.
  """
  @spec get(String.t(), any()) :: any()
  def get(key, default \\ nil) do
    case File.read(path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, map} when is_map(map) -> Map.get(map, key, default)
          _ -> default
        end

      _ ->
        default
    end
  rescue
    _ -> default
  end

  @doc """
  Read-modify-write: merges `{key, value}` into the existing flat JSON map
  at `path/0` (or `%{}` if the file doesn't exist/decode), creating the
  containing directory if needed, then writes the result back as JSON.
  Mirrors the mkdir-write-encode shape previously duplicated in
  `home_live.ex`'s `save_profile/1`.
  """
  @spec put(String.t(), any()) :: :ok
  def put(key, value) do
    current =
      case File.read(path()) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        _ ->
          %{}
      end

    File.mkdir_p!(dir())
    File.write!(path(), Jason.encode!(Map.put(current, key, value)))
    :ok
  end
end
