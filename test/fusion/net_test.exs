defmodule Fusion.NetTest do
  use ExUnit.Case, async: true
  doctest Fusion.Net

  describe "gen_port/0" do
    test "generates port in ephemeral range" do
      port = Fusion.Net.gen_port()
      assert port >= 49152
      assert port <= 65535
    end

    test "generates different ports on successive calls" do
      ports = for _ <- 1..10, do: Fusion.Net.gen_port()
      assert length(Enum.uniq(ports)) > 1
    end
  end

  describe "get_epmd_port/2" do
    test "returns default when no env var" do
      assert Fusion.Net.get_epmd_port(nil) == 4369
    end

    test "parses port from string" do
      assert Fusion.Net.get_epmd_port("5000") == 5000
    end
  end
end
