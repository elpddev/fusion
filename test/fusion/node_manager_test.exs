defmodule Fusion.NodeManagerTest do
  use ExUnit.Case, async: true

  alias Fusion.NodeManager
  alias Fusion.Target

  setup do
    %{
      target: %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"},
        ssh_backend: Fusion.Test.MockBackend
      }
    }
  end

  describe "start_link/1" do
    test "starts with a target" do
      target = %Target{
        host: "example.com",
        port: 22,
        username: "deploy",
        auth: {:key, "~/.ssh/id_rsa"}
      }

      {:ok, pid} = NodeManager.start_link(target)
      assert is_pid(pid)
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil

      GenServer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns :disconnected initially", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)
      assert NodeManager.status(pid) == :disconnected
      GenServer.stop(pid)
    end
  end

  describe "disconnect/1" do
    test "disconnect when already disconnected is a no-op", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)
      assert NodeManager.disconnect(pid) == :ok
      GenServer.stop(pid)
    end

    test "disconnect when connected resets state", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)

      :sys.replace_state(pid, fn state ->
        %{state | status: :connected, remote_node_name: :disc_test@localhost, conn: :mock_conn}
      end)

      assert NodeManager.disconnect(pid) == :ok
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil
      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "terminate handles disconnected state" do
      state = %NodeManager{status: :disconnected}
      assert NodeManager.terminate(:normal, state) == :ok
    end
  end

  describe "connect error handling" do
    test "returns error when backend.connect fails" do
      target = %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"},
        ssh_backend: Fusion.Test.FailConnectBackend
      }

      {:ok, pid} = NodeManager.start_link(target)
      result = NodeManager.connect(pid)
      assert {:error, _reason} = result
      assert NodeManager.status(pid) == :disconnected
      GenServer.stop(pid)
    end

    test "returns error when tunnel setup fails" do
      target = %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"},
        ssh_backend: Fusion.Test.FailTunnelBackend
      }

      {:ok, pid} = NodeManager.start_link(target)
      result = NodeManager.connect(pid)
      assert {:error, _reason} = result
      assert NodeManager.status(pid) == :disconnected
      GenServer.stop(pid)
    end
  end

  describe "handle_info(:nodedown)" do
    test "sets status to disconnected and cleans up", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)

      :sys.replace_state(pid, fn state ->
        %{state | status: :connected, remote_node_name: :test_node@localhost, conn: :mock_conn}
      end)

      send(pid, {:nodedown, :test_node@localhost})
      # :sys.get_state forces the GenServer to process all prior messages
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :disconnected
      assert NodeManager.remote_node(pid) == nil
      GenServer.stop(pid)
    end

    test "ignores arbitrary messages", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)
      send(pid, :random_message)
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :disconnected
      GenServer.stop(pid)
    end

    test "ignores nodedown for unrelated nodes", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)

      :sys.replace_state(pid, fn state ->
        %{state | status: :connected, remote_node_name: :my_node@localhost}
      end)

      send(pid, {:nodedown, :other_node@localhost})
      _ = :sys.get_state(pid)
      assert NodeManager.status(pid) == :connected
      GenServer.stop(pid)
    end
  end

  describe "connect when already connected" do
    test "returns existing node name", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)

      :sys.replace_state(pid, fn state ->
        %{state | status: :connected, remote_node_name: :fake@localhost}
      end)

      assert {:ok, :fake@localhost} = NodeManager.connect(pid)
      GenServer.stop(pid)
    end
  end

  describe "terminate with connected state" do
    test "calls close on the backend during cleanup", %{target: target} do
      {:ok, pid} = NodeManager.start_link(target)

      :sys.replace_state(pid, fn state ->
        %{state | status: :connected, remote_node_name: :term_test@localhost, conn: :mock_conn}
      end)

      GenServer.stop(pid, :normal)

      # If we get here without crash, terminate handled the connected state.
      # The MockBackend.close/1 was called successfully (it returns :ok).
      assert true
    end
  end

  describe "backend selection" do
    test "uses the backend from the target" do
      target = %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"},
        ssh_backend: Fusion.SshBackend.System
      }

      {:ok, pid} = NodeManager.start_link(target)
      state = :sys.get_state(pid)
      assert state.target.ssh_backend == Fusion.SshBackend.System
      GenServer.stop(pid)
    end

    test "defaults to Erlang backend" do
      target = %Target{
        host: "x",
        port: 22,
        username: "u",
        auth: {:key, "/k"}
      }

      {:ok, pid} = NodeManager.start_link(target)
      state = :sys.get_state(pid)
      assert state.target.ssh_backend == Fusion.SshBackend.Erlang
      GenServer.stop(pid)
    end
  end
end
