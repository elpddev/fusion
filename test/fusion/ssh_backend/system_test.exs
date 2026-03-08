defmodule Fusion.SshBackend.SystemTest do
  use ExUnit.Case, async: true

  import Fusion.Test.SshBackendSharedTests

  alias Fusion.SshBackend.System, as: Backend
  alias Fusion.Target

  assert_implements_ssh_backend(Backend)

  test "connect returns a conn struct with auth and remote" do
    target = %Target{
      host: "example.com",
      port: 22,
      username: "deploy",
      auth: {:key, "~/.ssh/id_rsa"},
      ssh_backend: Backend
    }

    assert {:ok, conn} = Backend.connect(target)
    assert conn.auth == %{username: "deploy", key_path: "~/.ssh/id_rsa"}
    assert conn.remote == %Fusion.Net.Spot{host: "example.com", port: 22}
  end

  test "connect with password auth" do
    target = %Target{
      host: "example.com",
      port: 2222,
      username: "admin",
      auth: {:password, "secret"},
      ssh_backend: Backend
    }

    assert {:ok, conn} = Backend.connect(target)
    assert conn.auth == %{username: "admin", password: "secret"}
    assert conn.remote == %Fusion.Net.Spot{host: "example.com", port: 2222}
  end

  test "close returns :ok" do
    target = %Target{
      host: "example.com",
      port: 22,
      username: "deploy",
      auth: {:key, "~/.ssh/id_rsa"},
      ssh_backend: Backend
    }

    {:ok, conn} = Backend.connect(target)
    assert :ok = Backend.close(conn)
  end
end
