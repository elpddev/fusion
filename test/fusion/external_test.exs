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
    auth = Keyword.get(opts, :auth)

    target =
      case {backend, auth} do
        {nil, nil} -> Docker.target()
        {nil, :password} -> Docker.target_password()
        {b, nil} -> %{Docker.target() | ssh_backend: b}
        {b, :password} -> %{Docker.target_password() | ssh_backend: b}
      end

    {:ok, manager} = NodeManager.start_link(target)

    case NodeManager.connect(manager) do
      {:ok, remote_node} ->
        try do
          fun.(manager, remote_node)
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
  #
  # Only the Erlang backend is tested through NodeManager because the System
  # backend's SSH tunnel cleanup is asynchronous — the remote sshd may hold
  # tunnel listeners after close, causing :not_accepted on the next test.
  # System backend is tested directly below (exec, tunnels, close).

  @tag timeout: 30_000
  test "connect and disconnect with Erlang backend (key auth)" do
    with_connected_node(
      fn _manager, remote_node ->
        assert is_atom(remote_node)
        assert remote_node in Node.list()
      end,
      backend: Fusion.SshBackend.Erlang
    )
  end

  @tag timeout: 30_000
  test "connect and disconnect with Erlang backend (password auth)" do
    with_connected_node(
      fn _manager, remote_node ->
        assert is_atom(remote_node)
        assert remote_node in Node.list()
      end,
      backend: Fusion.SshBackend.Erlang,
      auth: :password
    )
  end

  @tag timeout: 30_000
  test "connect with System backend (key auth) directly" do
    ensure_docker_available!()
    target = Docker.target() |> Map.put(:ssh_backend, Fusion.SshBackend.System)

    {:ok, conn} = Fusion.SshBackend.System.connect(target)
    {:ok, output} = Fusion.SshBackend.System.exec(conn, "echo system_key_ok")
    assert String.trim(output) == "system_key_ok"
    assert Fusion.SshBackend.System.close(conn) == :ok
  end

  @tag timeout: 30_000
  test "connect with System backend (password auth) directly" do
    ensure_docker_available!()
    target = Docker.target_password() |> Map.put(:ssh_backend, Fusion.SshBackend.System)

    {:ok, conn} = Fusion.SshBackend.System.connect(target)
    {:ok, output} = Fusion.SshBackend.System.exec(conn, "echo system_pass_ok")
    assert String.trim(output) == "system_pass_ok"
    assert Fusion.SshBackend.System.close(conn) == :ok
  end

  ## NodeManager: status and lifecycle

  @tag timeout: 30_000
  test "NodeManager status and remote_node APIs" do
    with_connected_node(fn manager, remote_node ->
      assert NodeManager.status(manager) == :connected
      assert NodeManager.remote_node(manager) == remote_node
    end)
  end

  @tag timeout: 60_000
  test "reconnect after disconnect" do
    ensure_docker_available!()
    target = Docker.target()
    {:ok, manager} = NodeManager.start_link(target)

    {:ok, node1} = NodeManager.connect(manager)
    assert node1 in Node.list()

    NodeManager.disconnect(manager)
    assert NodeManager.status(manager) == :disconnected
    assert NodeManager.remote_node(manager) == nil
    Process.sleep(1_000)

    {:ok, node2} = NodeManager.connect(manager)
    assert node2 in Node.list()
    assert node1 != node2

    NodeManager.disconnect(manager)
    GenServer.stop(manager)
    Process.sleep(1_000)
  end

  ## SshBackend: direct exec

  @tag timeout: 15_000
  test "Erlang backend: exec command directly" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.Erlang.connect(target)
    {:ok, output} = Fusion.SshBackend.Erlang.exec(conn, "echo hello")
    assert String.trim(output) == "hello"
    assert Fusion.SshBackend.Erlang.close(conn) == :ok
  end

  @tag timeout: 15_000
  test "System backend: exec command directly" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.System.connect(target)
    {:ok, output} = Fusion.SshBackend.System.exec(conn, "echo hello")
    assert String.trim(output) == "hello"
    assert Fusion.SshBackend.System.close(conn) == :ok
  end

  @tag timeout: 15_000
  test "Erlang backend: exec returns error for failing command" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.Erlang.connect(target)
    assert {:error, {:exit_status, code, _, _}} = Fusion.SshBackend.Erlang.exec(conn, "exit 42")
    assert code == 42
    Fusion.SshBackend.Erlang.close(conn)
  end

  @tag timeout: 15_000
  test "System backend: exec returns error for failing command" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.System.connect(target)
    assert {:error, {:exit_status, code, _, _}} = Fusion.SshBackend.System.exec(conn, "exit 42")
    assert code == 42
    Fusion.SshBackend.System.close(conn)
  end

  ## SshBackend: tunnels

  @tag timeout: 15_000
  test "Erlang backend: forward and reverse tunnels" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.Erlang.connect(target)

    [fwd_port, rev_port] = Fusion.Net.gen_unique_ports(2)

    assert {:ok, ^fwd_port} =
             Fusion.SshBackend.Erlang.forward_tunnel(conn, fwd_port, "127.0.0.1", fwd_port)

    assert {:ok, ^rev_port} =
             Fusion.SshBackend.Erlang.reverse_tunnel(conn, rev_port, "127.0.0.1", rev_port)

    Fusion.SshBackend.Erlang.close(conn)
  end

  @tag timeout: 15_000
  test "System backend: forward and reverse tunnels" do
    ensure_docker_available!()
    target = Docker.target()

    {:ok, conn} = Fusion.SshBackend.System.connect(target)

    [fwd_port, rev_port] = Fusion.Net.gen_unique_ports(2)

    assert {:ok, ^fwd_port} =
             Fusion.SshBackend.System.forward_tunnel(conn, fwd_port, "127.0.0.1", fwd_port)

    assert {:ok, ^rev_port} =
             Fusion.SshBackend.System.reverse_tunnel(conn, rev_port, "127.0.0.1", rev_port)

    Fusion.SshBackend.System.close(conn)
    Process.sleep(500)
  end

  ## TaskRunner: remote execution

  @tag timeout: 60_000
  test "full pipeline: connect, push module, execute, disconnect" do
    with_connected_node(fn _manager, remote_node ->
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
    with_connected_node(fn _manager, remote_node ->
      assert :ok = TaskRunner.push_module(remote_node, RemoteFuns)
      assert {:ok, 42} = TaskRunner.run(remote_node, RemoteFuns, :multiply, [21, 2])
    end)
  end

  @tag timeout: 30_000
  test "run_fun with auto-push of named function" do
    with_connected_node(fn _manager, remote_node ->
      assert {:ok, "hello from remote"} =
               TaskRunner.run_fun(remote_node, &RemoteFuns.hello/0)
    end)
  end

  @tag timeout: 60_000
  test "run system command on remote container" do
    with_connected_node(fn _manager, remote_node ->
      assert {:ok, {hostname, 0}} =
               TaskRunner.run(remote_node, System, :cmd, ["hostname", []])

      assert is_binary(hostname)
      assert String.length(String.trim(hostname)) > 0
    end)
  end

  @tag timeout: 60_000
  test "push multiple modules and use them together" do
    with_connected_node(fn _manager, remote_node ->
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
    with_connected_node(fn _manager, remote_node ->
      assert :ok = TaskRunner.push_module(remote_node, RemoteFuns)

      assert {:ok, %Fusion.Net.Spot{host: "test", port: 42}} =
               TaskRunner.run(remote_node, RemoteFuns, :make_spot, [42])
    end)
  end

  ## Error handling

  @tag timeout: 30_000
  test "run returns error for undefined function on remote" do
    with_connected_node(fn _manager, remote_node ->
      assert {:error, _} = TaskRunner.run(remote_node, :nonexistent_module, :nope, [])
    end)
  end

  @tag timeout: 30_000
  test "connection to unreachable host fails" do
    ensure_docker_available!()

    target = %Fusion.Target{
      host: "localhost",
      port: 19999,
      username: "fusion_test",
      auth: {:key, Docker.key_path()}
    }

    {:ok, manager} = NodeManager.start_link(target)
    assert {:error, _reason} = NodeManager.connect(manager, 5_000)
    GenServer.stop(manager)
  end
end
