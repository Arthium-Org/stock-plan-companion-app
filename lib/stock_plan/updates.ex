defmodule StockPlan.Updates do
  @moduledoc """
  Best-effort, unauthenticated check against the public GitHub Releases API
  for a newer app version than the one currently running (REL-02).

  Mirrors `StockPlan.FX.Sync`'s silent-fail-on-any-error contract exactly
  (D-06, D-08): offline, 404 (zero releases yet), rate-limited, or malformed
  payload all result in a silent no-op — never a crash, never a blocked
  boot. This module reads no credentials and sends no authentication —
  read-only, unauthenticated, no telemetry. Do not add a token/credential
  handling path to this module (D-08).

  The fetched result (including a truncated copy of the release notes) is
  cached in-memory only via `:persistent_term` (cleared on restart) — never
  written to disk. Only the *dismissed* update version is persisted to
  disk, via `StockPlan.Profile`, by the banner UI (plan 04-02).
  """

  @persistent_term_key {__MODULE__, :current}

  # Bound the in-memory notes payload so an oversized release body can't
  # grow persistent_term usage unboundedly (D-06/D-08, T-04-07).
  @max_notes_length 4_000

  @doc """
  Best-effort check; returns `:ok` always. Never raises. `repo_slug` must
  be read by the caller from `Application.get_env(:stock_plan,
  :update_check_repo_slug)` — never hardcode a repo slug here (the
  "three places must agree" invariant: in-app checker, landing-page
  links, release URLs).

  Silent-boot contract (D-06/D-08): every outcome — success, failure, or
  "on latest version" — either stores a banner-relevant state or clears
  it; nothing is ever logged or raised.
  """
  @spec check_async(String.t() | nil) :: :ok
  def check_async(nil), do: :ok
  def check_async(""), do: :ok

  def check_async(repo_slug) do
    case fetch_latest(repo_slug) do
      {:ok, tag, body} ->
        case evaluate_release(tag, body, running_version()) do
          {:update, tag} -> store({:update, tag, body})
          {:critical, tag} -> store({:critical, tag, body})
          {:up_to_date, _version} -> store(:none)
          :unavailable -> store(:none)
        end

      :error ->
        store(:none)
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Manual, on-demand check (footer "Check for updates" button, D1/D2).
  Unlike `check_async/1`, this returns a truthful outcome so the caller
  (the controller) can render a visible result. Never raises.

  Returns:
    - `{:update, tag_name}` / `{:critical, tag_name}` — a newer release
      exists; also stores the banner state (with notes) for the redirect.
    - `{:up_to_date, running_version}` — HTTP 200, parsed successfully,
      but not newer than the running version. Clears any stale banner.
    - `:unavailable` — non-200 (incl. 404), offline, timeout, or an
      unparseable/missing tag. NEVER conflated with `:up_to_date` (D1) —
      leaves any previously-stored banner state untouched, since we do
      not actually know the current release state.
  """
  @spec check_now(String.t() | nil) ::
          {:update, String.t()}
          | {:critical, String.t()}
          | {:up_to_date, String.t()}
          | :unavailable
  def check_now(nil), do: :unavailable
  def check_now(""), do: :unavailable

  def check_now(repo_slug) do
    case fetch_latest(repo_slug) do
      :error ->
        :unavailable

      {:ok, tag, body} ->
        case evaluate_release(tag, body, running_version()) do
          {:update, tag} ->
            store({:update, tag, body})
            {:update, tag}

          {:critical, tag} ->
            store({:critical, tag, body})
            {:critical, tag}

          {:up_to_date, version} ->
            store(:none)
            {:up_to_date, version}

          :unavailable ->
            :unavailable
        end
    end
  rescue
    _ -> :unavailable
  end

  # Performs the GitHub Releases API request shared by check_async/1 and
  # check_now/1. Returns {:ok, tag, body} on a well-formed 200 response
  # (body capped to @max_notes_length chars to bound memory, D-06/D-08),
  # or :error for every other status/shape (never raises here — the
  # rescue guards live in the public callers).
  defp fetch_latest(repo_slug) do
    url = "https://api.github.com/repos/#{repo_slug}/releases/latest"

    case Req.get(url,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000,
           headers: [
             {"user-agent", "StockPlanManager"},
             {"accept", "application/vnd.github+json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"tag_name" => tag} = release}} when is_binary(tag) ->
        body = String.slice(release["body"] || "", 0, @max_notes_length)
        {:ok, tag, body}

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  @doc """
  Pure evaluation: compares `tag_name` (a GitHub release tag, e.g.
  `"v1.6.0"`) against `running_version` (a bare semver string, e.g.
  `"1.5.0"`), and scans `release_body` for the severity-marker
  convention (D-07b). Never raises.

  Returns (D1 — the four states must stay distinct; "not newer" and
  "unparseable" must never collapse to the same value):
    - `{:update, tag_name}` — a newer, non-critical release
    - `{:critical, tag_name}` — a newer release marked critical AND the
      running version is below its `min_supported_version`
    - `{:up_to_date, running_version}` — both tag and running_version
      parsed, but the tag is not newer (`:eq` or `:lt`)
    - `:unavailable` — the tag or running_version failed to parse
  """
  @spec evaluate_release(String.t(), String.t(), String.t()) ::
          {:update, String.t()}
          | {:critical, String.t()}
          | {:up_to_date, String.t()}
          | :unavailable
  def evaluate_release(tag_name, release_body, running_version) do
    with {:ok, latest} <- Version.parse(strip_v(tag_name)),
         {:ok, current} <- Version.parse(running_version) do
      case Version.compare(latest, current) do
        :gt ->
          if critical?(release_body, running_version) do
            {:critical, tag_name}
          else
            {:update, tag_name}
          end

        _ ->
          {:up_to_date, running_version}
      end
    else
      _ -> :unavailable
    end
  end

  @doc """
  Returns the last resolved update state, or `:none` if no check has
  stored a result yet (e.g. before boot's async check completes, or on a
  fresh start). Notes ride alongside the tag, in-memory only.
  """
  @spec current() ::
          :none | {:update, String.t(), String.t()} | {:critical, String.t(), String.t()}
  def current do
    :persistent_term.get(@persistent_term_key, :none)
  end

  @doc "Stores the resolved update state in-memory (never written to disk)."
  @spec store(:none | {:update, String.t(), String.t()} | {:critical, String.t(), String.t()}) ::
          :ok
  def store(result) do
    :persistent_term.put(@persistent_term_key, result)
    :ok
  end

  # Severity-marker convention (D-07b): a release is critical iff its body
  # contains BOTH a `Severity: critical` line AND a `min_supported_version:
  # A.B.C` line, AND the running version is strictly below that minimum.
  # Regex match only — release_body is untrusted remote input and is
  # never rendered/eval'd as code.
  defp critical?(release_body, running_version) do
    with [_, min_supported] <-
           Regex.run(~r/^min_supported_version:\s*([\d.]+)\s*$/mi, release_body),
         true <- Regex.match?(~r/^Severity:\s*critical\s*$/mi, release_body),
         {:ok, min_v} <- Version.parse(min_supported),
         {:ok, current} <- Version.parse(running_version) do
      Version.compare(current, min_v) == :lt
    else
      _ -> false
    end
  end

  defp strip_v("v" <> rest), do: rest
  defp strip_v(other), do: other

  defp running_version do
    case Application.spec(:stock_plan, :vsn) do
      vsn when is_list(vsn) -> to_string(vsn)
      vsn when is_binary(vsn) -> vsn
    end
  end
end
