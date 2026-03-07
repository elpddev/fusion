defmodule Fusion.SshBackend.ErlangTest do
  use ExUnit.Case, async: true

  alias Fusion.SshBackend.Erlang, as: Backend
  alias Fusion.Target

  describe "connect_opts/1" do
    test "builds password auth options" do
      target = %Target{host: "h", port: 22, username: "user", auth: {:password, "secret"}}
      opts = Backend.connect_opts(target)

      assert Keyword.get(opts, :user) == ~c"user"
      assert Keyword.get(opts, :password) == ~c"secret"
      assert Keyword.get(opts, :silently_accept_hosts) == true
      assert Keyword.get(opts, :user_interaction) == false
    end

    test "builds key auth options" do
      target = %Target{host: "h", port: 22, username: "user", auth: {:key, "/home/user/.ssh/id_ed25519"}}
      opts = Backend.connect_opts(target)

      assert Keyword.get(opts, :user) == ~c"user"
      assert Keyword.get(opts, :key_cb) == {Fusion.SshKeyProvider, key_path: "/home/user/.ssh/id_ed25519"}
      assert Keyword.get(opts, :silently_accept_hosts) == true
      assert Keyword.get(opts, :user_interaction) == false
      refute Keyword.has_key?(opts, :password)
    end
  end

  test "implements the SshBackend behaviour" do
    behaviours =
      Backend.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert Fusion.SshBackend in behaviours
  end
end
