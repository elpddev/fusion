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

  defp find_ssh_key do
    ~w(~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa)
    |> Enum.map(&Path.expand/1)
    |> Enum.find(&File.exists?/1)
  end

  defp ssh_to_localhost_works?(ssh_key) do
    user = System.get_env("USER")

    {_output, exit_code} =
      System.cmd(
        "ssh",
        [
          "-i",
          ssh_key,
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

    exit_code == 0
  end

  defp skip_unless_ssh_available do
    case find_ssh_key() do
      nil ->
        {:skip, "No SSH key found in ~/.ssh/"}

      ssh_key ->
        if ssh_to_localhost_works?(ssh_key) do
          {:ok, ssh_key}
        else
          {:skip, "SSH to localhost not configured (add local key to authorized_keys)"}
        end
    end
  end

  @tag timeout: 30_000
  test "connect to localhost, bootstrap remote node, verify cluster connection" do
    case skip_unless_ssh_available() do
      {:skip, reason} ->
        IO.puts("SKIP: #{reason}")

      {:ok, ssh_key} ->
        user = System.get_env("USER")

        target = %Target{
          host: "localhost",
          port: 22,
          username: user,
          auth: {:key, ssh_key}
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
            IO.puts("SKIP: Local node not alive (run with --sname)")

          {:error, reason} ->
            flunk("Failed to connect: #{inspect(reason)}")
        end

        GenServer.stop(manager)
    end
  end
end
