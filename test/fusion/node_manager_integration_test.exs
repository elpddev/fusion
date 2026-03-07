defmodule Fusion.NodeManagerIntegrationTest do
  @moduledoc """
  Integration tests that SSH to localhost to test real node bootstrapping.
  Run with: mix test --include integration
  Requires: SSH server running locally, key-based auth configured for current user.
  """
  use ExUnit.Case

  alias Fusion.NodeManager
  alias Fusion.Target

  @moduletag :integration

  @ssh_key ~w(~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa)
           |> Enum.map(&Path.expand/1)
           |> Enum.find(&File.exists?/1)

  @ssh_available (case @ssh_key do
                    nil ->
                      IO.puts("\n  Integration tests skipped: No SSH key found in ~/.ssh/")
                      false

                    key ->
                      user = System.get_env("USER")

                      {_output, exit_code} =
                        System.cmd(
                          "ssh",
                          [
                            "-i",
                            key,
                            "-o",
                            "BatchMode=yes",
                            "-o",
                            "ConnectTimeout=3",
                            "#{user}@localhost",
                            "echo",
                            "ok"
                          ],
                          stderr_to_stdout: true
                        )

                      if exit_code != 0 do
                        IO.puts(
                          "\n  Integration tests skipped: SSH to localhost not configured (add local key to authorized_keys)"
                        )
                      end

                      exit_code == 0
                  end)

  unless @ssh_available do
    @moduletag :skip
  end

  for backend <- [Fusion.SshBackend.Erlang, Fusion.SshBackend.System] do
    backend_name = backend |> Module.split() |> List.last()

    @tag timeout: 30_000
    test "connect with #{backend_name} backend" do
      user = System.get_env("USER")

      target = %Target{
        host: "localhost",
        port: 22,
        username: user,
        auth: {:key, @ssh_key},
        ssh_backend: unquote(backend)
      }

      {:ok, manager} = NodeManager.start_link(target)

      case NodeManager.connect(manager) do
        {:ok, remote_node} ->
          assert is_atom(remote_node)
          assert remote_node in Node.list()
          assert NodeManager.status(manager) == :connected

          assert NodeManager.disconnect(manager) == :ok
          assert NodeManager.status(manager) == :disconnected
          refute remote_node in Node.list()

        {:error, :local_node_not_alive} ->
          flunk("Local node not alive (run with --sname)")

        {:error, reason} ->
          flunk("Failed with #{unquote(backend_name)}: #{inspect(reason)}")
      end

      GenServer.stop(manager)
    end
  end

  @tag timeout: 15_000
  test "Erlang backend: connect and exec on localhost" do
    user = System.get_env("USER")

    target = %Target{
      host: "localhost",
      port: 22,
      username: user,
      auth: {:key, @ssh_key},
      ssh_backend: Fusion.SshBackend.Erlang
    }

    {:ok, conn} = Fusion.SshBackend.Erlang.connect(target)
    {:ok, output} = Fusion.SshBackend.Erlang.exec(conn, "echo hello")
    assert String.trim(output) == "hello"
    assert Fusion.SshBackend.Erlang.close(conn) == :ok
  end
end
