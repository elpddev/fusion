defmodule Fusion.SupervisionTest do
  use ExUnit.Case

  describe "application supervisor" do
    test "Fusion.Supervisor is running" do
      assert Process.whereis(Fusion.Supervisor) != nil
    end

    test "Fusion.TunnelSupervisor is running" do
      assert Process.whereis(Fusion.TunnelSupervisor) != nil
    end

    test "TunnelSupervisor is a DynamicSupervisor" do
      pid = Process.whereis(Fusion.TunnelSupervisor)

      assert DynamicSupervisor.count_children(pid) == %{
               active: 0,
               specs: 0,
               supervisors: 0,
               workers: 0
             }
    end
  end

  describe "SshPortTunnel terminate/2" do
    test "terminate handles nil os_pid gracefully" do
      # GenServer that never started a tunnel should terminate cleanly
      state = %Fusion.SshPortTunnel{os_pid: nil}
      assert Fusion.SshPortTunnel.terminate(:normal, state) == :ok
    end
  end

  describe "PortRelay terminate/2" do
    test "terminate handles nil os_pid gracefully" do
      state = %Fusion.PortRelay{os_pid: nil}
      assert Fusion.PortRelay.terminate(:normal, state) == :ok
    end
  end

  describe "UdpTunnel terminate/2" do
    test "terminate handles nil os_pid gracefully" do
      state = %Fusion.UdpTunnel{os_pid: nil}
      assert Fusion.UdpTunnel.terminate(:normal, state) == :ok
    end
  end
end
