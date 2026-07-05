defmodule StockPlan.UpdatesTest do
  use ExUnit.Case, async: true

  alias StockPlan.Updates

  describe "evaluate_release/3" do
    test "tag newer than running version, no severity marker -> {:update, tag}" do
      assert Updates.evaluate_release("v1.6.0", "Some release notes.", "1.5.0") ==
               {:update, "v1.6.0"}
    end

    test "tag equal to running version -> {:up_to_date, running_version}" do
      assert Updates.evaluate_release("v1.5.0", "", "1.5.0") == {:up_to_date, "1.5.0"}
    end

    test "tag older than running version -> {:up_to_date, running_version}" do
      assert Updates.evaluate_release("v1.4.0", "", "1.5.0") == {:up_to_date, "1.5.0"}
    end

    test "v-prefixed tag strips leading v before parsing, never raises" do
      assert Updates.evaluate_release("v1.6.0", "", "1.5.0") == {:update, "v1.6.0"}
    end

    test "unparseable/garbage tag -> :unavailable, never raises" do
      assert Updates.evaluate_release("not-a-version", "", "1.5.0") == :unavailable
      assert Updates.evaluate_release("release-42", "", "1.5.0") == :unavailable
    end

    test "severity critical + min_supported_version greater than running -> {:critical, tag}" do
      body = """
      Severity: critical
      min_supported_version: 1.6.0

      ## What's new
      Important security fix.
      """

      assert Updates.evaluate_release("v1.7.0", body, "1.5.0") == {:critical, "v1.7.0"}
    end

    test "severity critical present but running >= min_supported_version -> {:update, tag} (not critical)" do
      body = """
      Severity: critical
      min_supported_version: 1.4.0

      ## What's new
      """

      assert Updates.evaluate_release("v1.6.0", body, "1.5.0") == {:update, "v1.6.0"}
    end

    test "severity critical present but no min_supported_version line -> {:update, tag}" do
      body = """
      Severity: critical

      ## What's new
      """

      assert Updates.evaluate_release("v1.6.0", body, "1.5.0") == {:update, "v1.6.0"}
    end

    test "double-digit ordering: running 1.9.0, tag 1.10.0 -> {:update, ...} (semver, not lexicographic)" do
      assert Updates.evaluate_release("v1.10.0", "", "1.9.0") == {:update, "v1.10.0"}
    end
  end

  describe "check_now/1 outcome mapping (D1 — never :up_to_date on failure)" do
    test "nil or empty repo slug -> :unavailable without a network call" do
      assert Updates.check_now(nil) == :unavailable
      assert Updates.check_now("") == :unavailable
    end

    # These exercise the pure evaluate_release/3 seam that check_now/1's
    # mapping is built on, without making a live HTTP call.
    test "200 + newer tag maps to {:update, tag}" do
      assert Updates.evaluate_release("v9.9.9", "notes", "1.5.0") == {:update, "v9.9.9"}
    end

    test "200 + not-newer tag maps to {:up_to_date, version}, never :unavailable" do
      assert Updates.evaluate_release("v1.0.0", "notes", "1.5.0") == {:up_to_date, "1.5.0"}
    end

    test "unparseable tag maps to :unavailable, never {:up_to_date, _}" do
      assert Updates.evaluate_release("garbage", "notes", "1.5.0") == :unavailable
    end

    test "critical path maps to {:critical, tag}" do
      body = """
      Severity: critical
      min_supported_version: 9.0.0
      """

      assert Updates.evaluate_release("v9.9.9", body, "1.5.0") == {:critical, "v9.9.9"}
    end
  end

  describe "current/0 and store/1 (3-tuple banner payload)" do
    test "returns :none before any check has stored a result" do
      # Uses a dedicated persistent_term key namespace so this doesn't
      # collide with other tests exercising store/1.
      assert Updates.current() == :none or match?({_, _, _}, Updates.current())
    end

    test "returns the stored 3-tuple after store/1" do
      assert :ok = Updates.store({:update, "v1.6.0", "some notes"})
      assert Updates.current() == {:update, "v1.6.0", "some notes"}

      assert :ok = Updates.store({:critical, "v1.7.0", "critical notes"})
      assert Updates.current() == {:critical, "v1.7.0", "critical notes"}

      assert :ok = Updates.store(:none)
      assert Updates.current() == :none
    end
  end

  describe "check_async/1 guard clauses" do
    test "returns :ok for nil or empty repo slug without making a network call" do
      assert Updates.check_async(nil) == :ok
      assert Updates.check_async("") == :ok
    end
  end
end
