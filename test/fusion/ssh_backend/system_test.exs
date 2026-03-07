defmodule Fusion.SshBackend.SystemTest do
  use ExUnit.Case, async: true

  alias Fusion.SshBackend.System, as: Backend
  alias Fusion.Target

  test "implements the SshBackend behaviour" do
    behaviours =
      Backend.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert Fusion.SshBackend in behaviours
  end

  test "exports all required callback functions" do
    Code.ensure_loaded!(Backend)
    assert function_exported?(Backend, :connect, 1)
    assert function_exported?(Backend, :forward_tunnel, 4)
    assert function_exported?(Backend, :reverse_tunnel, 4)
    assert function_exported?(Backend, :exec, 2)
    assert function_exported?(Backend, :exec_async, 2)
    assert function_exported?(Backend, :close, 1)
  end

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
