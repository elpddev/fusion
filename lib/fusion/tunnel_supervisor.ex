defmodule Fusion.TunnelSupervisor do
  @moduledoc "Helpers for starting tunnel processes under the DynamicSupervisor."

  alias Fusion.SshPortTunnel
  alias Fusion.PortRelay

  @doc "Start an SSH port tunnel under supervision."
  def start_ssh_tunnel(auth, remote, direction, from_port, to_spot) do
    spec = %{
      id: make_ref(),
      start: {SshPortTunnel, :start_link, [auth, remote, direction, from_port, to_spot]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(Fusion.TunnelSupervisor, spec)
  end

  @doc "Start a local port relay under supervision."
  def start_port_relay(from_port, from_type, to_port, to_type) do
    spec = %{
      id: make_ref(),
      start: {PortRelay, :start_link, [from_port, from_type, to_port, to_type]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(Fusion.TunnelSupervisor, spec)
  end

  @doc "Start a remote port relay under supervision."
  def start_port_relay(auth, remote, from_port, from_type, to_port, to_type) do
    spec = %{
      id: make_ref(),
      start: {PortRelay, :start_link, [auth, remote, from_port, from_type, to_port, to_type]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(Fusion.TunnelSupervisor, spec)
  end
end
