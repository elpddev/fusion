defmodule Fusion.SshBackend.ErlangTest do
  use ExUnit.Case, async: true

  alias Fusion.SshBackend.Erlang, as: Backend

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

  test "ensures :ssh application is started" do
    # The Erlang backend calls :ssh.start() in connect/1.
    # We can verify the application is available (it's in extra_applications).
    started_apps = Application.started_applications() |> Enum.map(&elem(&1, 0))
    assert :ssh in started_apps
  end
end
