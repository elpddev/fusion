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

  defp ensure_docker_available! do
    unless Docker.available?() do
      flunk("Docker container not running (cd test/docker && ./run.sh start)")
    end

    unless Docker.ssh_works?() do
      flunk("SSH to Docker container failed")
    end
  end

  defp with_connected_node(fun, opts \\ []) do
    ensure_docker_available!()
    backend = Keyword.get(opts, :backend)
    target = if backend, do: %{Docker.target() | ssh_backend: backend}, else: Docker.target()
    {:ok, manager} = NodeManager.start_link(target)

    case NodeManager.connect(manager) do
      {:ok, remote_node} ->
        try do
          fun.(remote_node)
        after
          NodeManager.disconnect(manager)
          GenServer.stop(manager)
          # Allow remote sshd to release tunnel listeners before the
          # next test tries to bind the same local node port.
          Process.sleep(1_000)
        end

      {:error, :local_node_not_alive} ->
        flunk("Local node not alive (run with --sname flag)")

      {:error, reason} ->
        flunk("Connection to Docker container failed: #{inspect(reason)}")
    end
  end

  ## NodeManager: backend connectivity

  for backend <- [Fusion.SshBackend.Erlang, Fusion.SshBackend.System] do
    backend_name = backend |> Module.split() |> List.last()

    @tag timeout: 30_000
    test "connect and disconnect with #{backend_name} backend" do
      with_connected_node(
        fn remote_node ->
          assert is_atom(remote_node)
          assert remote_node in Node.list()
        end,
        backend: unquote(backend)
      )
    end
  end

  @tag timeout: 15_000
  test "Erlang backend: exec command directly" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.Erlang.connect(target)
    {:ok, output} = Fusion.SshBackend.Erlang.exec(conn, "echo hello")
    assert String.trim(output) == "hello"
    assert Fusion.SshBackend.Erlang.close(conn) == :ok
  end

  ## TaskRunner: remote execution

  @tag timeout: 60_000
  test "full pipeline: connect, push module, execute, disconnect" do
    with_connected_node(fn remote_node ->
      assert {:ok, 3} = TaskRunner.run(remote_node, Kernel, :+, [1, 2])

      assert {:ok, "hello from remote"} =
               TaskRunner.run_fun(remote_node, &RemoteFuns.hello/0)

      assert :ok = TaskRunner.push_module(remote_node, Fusion.Net)
      assert {:ok, port} = TaskRunner.run(remote_node, Fusion.Net, :gen_port, [])
      assert is_integer(port)
      assert port > 0

      assert {:ok, remote_pid} =
               TaskRunner.run_fun(remote_node, &RemoteFuns.get_self/0)

      assert node(remote_pid) == remote_node
      assert remote_node != node()
    end)
  end

  @tag timeout: 30_000
  test "run function on remote node" do
    with_connected_node(fn remote_node ->
      assert :ok = TaskRunner.push_module(remote_node, RemoteFuns)
      assert {:ok, 42} = TaskRunner.run(remote_node, RemoteFuns, :multiply, [21, 2])
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
      assert :ok = TaskRunner.push_module(remote_node, RemoteFuns)

      assert {:ok, %Fusion.Net.Spot{host: "test", port: 42}} =
               TaskRunner.run(remote_node, RemoteFuns, :make_spot, [42])
    end)
  end
end
