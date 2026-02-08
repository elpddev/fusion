defmodule Fusion.ExternalTest do
  @moduledoc """
  End-to-end tests against a Docker container with SSH + Elixir.

  Prerequisites:
    cd test/docker && ./run.sh start

  Run with:
    elixir --sname fusion_test@localhost -S mix test --include external
  """
  use ExUnit.Case

  alias Fusion.NodeManager
  alias Fusion.TaskRunner
  alias Fusion.Test.Helpers.Docker
  alias Fusion.Test.Helpers.RemoteFuns

  @moduletag :external

  defp skip_unless_docker_available do
    cond do
      not Docker.available?() ->
        IO.puts("SKIP: Docker container not running (cd test/docker && ./run.sh start)")
        :skip

      not Docker.ssh_works?() ->
        IO.puts("SKIP: SSH to Docker container failed")
        :skip

      true ->
        :ok
    end
  end

  defp with_connected_node(fun) do
    case skip_unless_docker_available() do
      :skip ->
        :ok

      :ok ->
        target = Docker.target()
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
            IO.puts("SKIP: Run with --sname flag")

          {:error, reason} ->
            flunk("Connection to Docker container failed: #{inspect(reason)}")
        end
    end
  end

  @tag timeout: 60_000
  test "full pipeline: connect, push module, execute, disconnect" do
    with_connected_node(fn remote_node ->
      # Verify basic arithmetic works via MFA
      assert {:ok, 3} = TaskRunner.run(remote_node, Kernel, :+, [1, 2])

      # Run function from a compiled helper module via run_fun
      assert {:ok, "hello from remote"} =
               TaskRunner.run_fun(remote_node, &RemoteFuns.hello/0)

      # Push a custom module and call it
      assert :ok = TaskRunner.push_module(remote_node, Fusion.Net)
      assert {:ok, port} = TaskRunner.run(remote_node, Fusion.Net, :gen_port, [])
      assert is_integer(port)
      assert port >= 49152

      # Verify the remote node is a separate BEAM instance
      assert {:ok, remote_pid} =
               TaskRunner.run_fun(remote_node, &RemoteFuns.get_self/0)

      assert node(remote_pid) == remote_node
      assert remote_node != node()
    end)
  end

  @tag timeout: 60_000
  test "run system command on remote container" do
    with_connected_node(fn remote_node ->
      assert {:ok, {hostname, 0}} =
               TaskRunner.run(remote_node, System, :cmd, ["hostname", []])

      assert is_binary(hostname)
      assert String.length(String.trim(hostname)) > 0
    end)
  end

  @tag timeout: 60_000
  test "push multiple modules and use them together" do
    with_connected_node(fn remote_node ->
      assert :ok =
               TaskRunner.push_modules(remote_node, [
                 Fusion.Net,
                 Fusion.Net.Spot,
                 RemoteFuns
               ])

      assert {:ok, spot} =
               TaskRunner.run(remote_node, RemoteFuns, :make_spot, [55_000])

      assert %Fusion.Net.Spot{host: "test", port: 55_000} = spot
    end)
  end

  @tag timeout: 60_000
  test "automatic transitive dependency pushing" do
    with_connected_node(fn remote_node ->
      # Push ONLY RemoteFuns - it references Fusion.Net.Spot via make_spot/1.
      # The dependency should be resolved and pushed automatically.
      assert :ok = TaskRunner.push_module(remote_node, RemoteFuns)

      # Call make_spot which creates a Fusion.Net.Spot struct.
      # This would fail with UndefinedFunctionError if Spot wasn't auto-pushed.
      assert {:ok, %Fusion.Net.Spot{host: "test", port: 42}} =
               TaskRunner.run(remote_node, RemoteFuns, :make_spot, [42])
    end)
  end
end
