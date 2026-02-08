defmodule Fusion.TaskRunnerIntegrationTest do
  @moduledoc """
  Integration tests for TaskRunner over a real SSH connection.
  Run with: mix test --include integration
  """
  use ExUnit.Case

  alias Fusion.NodeManager
  alias Fusion.TaskRunner
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

  defp with_connected_node(fun) do
    case find_ssh_key() do
      nil ->
        IO.puts("SKIP: No SSH key found")

      ssh_key ->
        unless ssh_to_localhost_works?(ssh_key) do
          IO.puts("SKIP: SSH to localhost not configured")
        else
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
              try do
                fun.(remote_node)
              after
                NodeManager.disconnect(manager)
                GenServer.stop(manager)
              end

            {:error, :local_node_not_alive} ->
              IO.puts("SKIP: Local node not alive")

            {:error, reason} ->
              flunk("Connection failed: #{inspect(reason)}")
          end
        end
    end
  end

  @tag timeout: 30_000
  test "run MFA on remote node" do
    with_connected_node(fn remote_node ->
      assert {:ok, 3} = TaskRunner.run(remote_node, Kernel, :+, [1, 2])
    end)
  end

  @tag timeout: 30_000
  test "run anonymous function on remote node" do
    with_connected_node(fn remote_node ->
      assert {:ok, 42} = TaskRunner.run_fun(remote_node, fn -> 21 * 2 end)
    end)
  end

  @tag timeout: 30_000
  test "push and run custom module on remote node" do
    with_connected_node(fn remote_node ->
      assert :ok = TaskRunner.push_module(remote_node, Fusion.Net)
      assert {:ok, port} = TaskRunner.run(remote_node, Fusion.Net, :gen_port, [])
      assert is_integer(port)
      assert port >= 49152
    end)
  end
end
