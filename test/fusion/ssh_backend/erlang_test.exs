defmodule Fusion.SshBackend.ErlangTest do
  use ExUnit.Case, async: true

  import Fusion.Test.SshBackendSharedTests

  alias Fusion.SshBackend.Erlang, as: Backend

  assert_implements_ssh_backend(Backend)

  test "ensures :ssh application is started" do
    started_apps = Application.started_applications() |> Enum.map(&elem(&1, 0))
    assert :ssh in started_apps
  end

  test "close/1 returns :ok even with invalid connection" do
    assert :ok = Backend.close(:not_a_real_connection)
  end
end
