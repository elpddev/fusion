defmodule Fusion.NodeManagerTest do
  use ExUnit.Case, async: true

  alias Fusion.NodeManager
  alias Fusion.Target

  describe "start_link/1" do
    test "starts with a target" do
      pid = start_manager()
      assert is_pid(pid)
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil
    end
  end

  describe "status/1" do
    test "returns :disconnected initially" do
      pid = start_manager()
      assert NodeManager.status(pid) == :disconnected
    end
  end

  describe "disconnect/1" do
    test "disconnect when already disconnected is a no-op" do
      pid = start_manager()
      assert NodeManager.disconnect(pid) == :ok
    end

    test "disconnect when connected resets state and calls close" do
      conn_id = :disc_conn
      table = :ets.new(:"tracking_mock_#{conn_id}", [:named_table, :public, :set])
      on_exit(fn -> if :ets.whereis(table) != :undefined, do: :ets.delete(table) end)

      pid = start_manager(ssh_backend: Fusion.Test.TrackingMockBackend)
      force_connected(pid, :disc_test@localhost, conn_id)

      assert NodeManager.disconnect(pid) == :ok
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil

      assert [{:close_count, 1}] = :ets.lookup(table, :close_count)
    end
  end

  describe "terminate/2" do
    test "calls close on the backend during cleanup" do
      conn_id = :term_conn
      table = :ets.new(:"tracking_mock_#{conn_id}", [:named_table, :public, :set])
      on_exit(fn -> if :ets.whereis(table) != :undefined, do: :ets.delete(table) end)

      pid = start_manager(ssh_backend: Fusion.Test.TrackingMockBackend)
      force_connected(pid, :term_test@localhost, conn_id)

      GenServer.stop(pid, :normal)

      assert [{:close_count, 1}] = :ets.lookup(table, :close_count)
    end
  end

  describe "connect error handling" do
    @tag :distributed
    test "returns error when backend.connect fails" do
      pid = start_manager(ssh_backend: Fusion.Test.FailConnectBackend)
      assert {:error, :connection_refused} = NodeManager.connect(pid)
      assert NodeManager.status(pid) == :disconnected
    end

    @tag :distributed
    test "returns error when tunnel setup fails" do
      pid = start_manager(ssh_backend: Fusion.Test.FailTunnelBackend)
      assert {:error, :tunnel_failed} = NodeManager.connect(pid)
      assert NodeManager.status(pid) == :disconnected
    end

    @tag :distributed
    test "returns error when exec_async fails" do
      pid = start_manager(ssh_backend: Fusion.Test.FailExecAsyncBackend)
      assert {:error, :exec_async_failed} = NodeManager.connect(pid)
      assert NodeManager.status(pid) == :disconnected
    end

    @tag :not_distributed
    test "returns error when local node is not alive" do
      pid = start_manager()
      assert {:error, :local_node_not_alive} = NodeManager.connect(pid)
      assert NodeManager.status(pid) == :disconnected
    end
  end

  describe "handle_info(:nodedown)" do
    test "sets status to disconnected and cleans up" do
      pid = start_manager()
      force_connected(pid, :test_node@localhost)

      send(pid, {:nodedown, :test_node@localhost})
      # :sys.get_state forces the GenServer to process all prior messages
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil
    end

    test "ignores arbitrary messages" do
      pid = start_manager()
      send(pid, :random_message)
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :disconnected
    end

    test "ignores nodedown for unrelated nodes" do
      pid = start_manager()
      force_connected(pid, :my_node@localhost)

      send(pid, {:nodedown, :other_node@localhost})
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :connected
    end
  end

  describe "connect when already connected" do
    test "returns existing node name" do
      pid = start_manager()
      force_connected(pid, :fake@localhost)

      assert {:ok, :fake@localhost} = NodeManager.connect(pid)
    end
  end

  describe "backend validation" do
    test "raises for module that does not implement SshBackend" do
      Process.flag(:trap_exit, true)

      assert {:error, {%ArgumentError{message: msg}, _}} =
               NodeManager.start_link(build_target(ssh_backend: String))

      assert msg =~ "does not implement"
    end
  end

  describe "backend selection" do
    test "uses the backend from the target" do
      pid = start_manager(ssh_backend: Fusion.SshBackend.System)
      state = :sys.get_state(pid)
      assert state.target.ssh_backend == Fusion.SshBackend.System
    end

    test "defaults to Erlang backend" do
      pid = start_manager()
      state = :sys.get_state(pid)
      assert state.target.ssh_backend == Fusion.SshBackend.Erlang
    end
  end

  ## Helpers

  defp start_manager(overrides \\ []) do
    target = build_target(overrides)
    {:ok, pid} = NodeManager.start_link(target)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  defp force_connected(pid, node_name, conn \\ :mock_conn) do
    :sys.replace_state(pid, fn state ->
      %{state | status: :connected, remote_node_name: node_name, conn: conn}
    end)
  end

  defp build_target(overrides) do
    struct(
      %Target{host: "x", port: 22, username: "u", auth: {:key, "/k"}},
      overrides
    )
  end
end
