defmodule StockPlan.ProfileTest do
  use ExUnit.Case, async: false

  alias StockPlan.Profile

  setup do
    original_path = Application.get_env(:stock_plan, :profile_path)

    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "stock_plan_profile_test_#{System.unique_integer([:positive])}.json"
      )

    Application.put_env(:stock_plan, :profile_path, tmp_path)

    on_exit(fn ->
      File.rm(tmp_path)
      Application.put_env(:stock_plan, :profile_path, original_path)
    end)

    %{tmp_path: tmp_path}
  end

  describe "get/2 and put/2" do
    test "round-trip: put then get returns the stored value", %{tmp_path: tmp_path} do
      refute File.exists?(tmp_path)

      assert :ok = Profile.put("dismissed_update_version", "1.6.0")
      assert Profile.get("dismissed_update_version", nil) == "1.6.0"
    end

    test "get/2 on a missing file returns the supplied default without raising" do
      assert Profile.get("dismissed_update_version", "default") == "default"
      assert Profile.get("anything", nil) == nil
    end

    test "put/2 preserves other existing keys on merge" do
      assert :ok = Profile.put("name", "Kiran")
      assert :ok = Profile.put("dismissed_update_version", "1.6.0")

      assert Profile.get("name", nil) == "Kiran"
      assert Profile.get("dismissed_update_version", nil) == "1.6.0"
    end

    test "get/2 returns default when the file contains invalid JSON", %{tmp_path: tmp_path} do
      File.mkdir_p!(Path.dirname(tmp_path))
      File.write!(tmp_path, "not valid json")

      assert Profile.get("anything", "fallback") == "fallback"
    end
  end
end
