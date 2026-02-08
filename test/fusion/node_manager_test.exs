defmodule Fusion.NodeManagerTest do
  use ExUnit.Case

  alias Fusion.NodeManager
  alias Fusion.Target

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
    test "returns :disconnected initially" do
      target = %Target{host: "x", port: 22, username: "u", auth: {:key, "/k"}}
      {:ok, pid} = NodeManager.start_link(target)
      assert NodeManager.status(pid) == :disconnected
      GenServer.stop(pid)
    end
  end

  describe "disconnect/1" do
    test "disconnect when already disconnected is a no-op" do
      target = %Target{host: "x", port: 22, username: "u", auth: {:key, "/k"}}
      {:ok, pid} = NodeManager.start_link(target)
      assert NodeManager.disconnect(pid) == :ok
      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "terminate handles disconnected state" do
      state = %NodeManager{status: :disconnected}
      assert NodeManager.terminate(:normal, state) == :ok
    end
  end
end
