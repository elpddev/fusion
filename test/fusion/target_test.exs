defmodule Fusion.TargetTest do
  use ExUnit.Case, async: true

  alias Fusion.Target

  describe "ssh_backend" do
    test "defaults to Fusion.SshBackend.Erlang" do
      target = %Target{host: "x", port: 22, username: "u", auth: {:key, "/k"}}
      assert target.ssh_backend == Fusion.SshBackend.Erlang
    end

    test "can be set to System backend" do
      target = %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"},
        ssh_backend: Fusion.SshBackend.System
      }

      assert target.ssh_backend == Fusion.SshBackend.System
    end
  end
end
