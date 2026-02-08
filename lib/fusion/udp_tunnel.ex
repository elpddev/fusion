defmodule Fusion.UdpTunnel do
  @moduledoc "GenServer for UDP tunneling over TCP SSH tunnels."

  use GenServer
  require Logger

  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot
  alias Fusion.Net
  alias Fusion.PortRelay

  defstruct status: :off,
            ssh_tunnel_port: nil,
            os_pid: nil,
            auth: nil,
            remote: nil,
            direction: nil,
            from_port: nil,
            to_spot: nil,
            mediator_tcp_from_port: nil,
            mediator_tcp_to_port: nil

  ## Public API

  def start_link(auth, remote, direction, from_port, to_spot) do
    GenServer.start_link(__MODULE__, [auth, remote, direction, from_port, to_spot])
  end

  def start_link_now(auth, remote, direction, from_port, to_spot) do
    {:ok, server} = res = start_link(auth, remote, direction, from_port, to_spot)
    :ok = start_tunnel(server)
    res
  end

  def start_tunnel(server) do
    GenServer.call(server, :start_tunnel)
  end

  ## Callbacks

  @impl true
  def init([auth, remote, direction, from_port, to_spot]) do
    {:ok,
     %__MODULE__{
       auth: auth,
       remote: remote,
       direction: direction,
       from_port: from_port,
       to_spot: to_spot
     }}
  end

  @impl true
  def handle_call(:start_tunnel, _from, %__MODULE__{status: :off} = state) do
    mediator_tcp_from_port = Net.gen_port()
    mediator_tcp_to_port = mediator_tcp_from_port

    cmd =
      Ssh.cmd_port_tunnel(
        state.auth,
        state.remote,
        mediator_tcp_from_port,
        %Spot{host: "localhost", port: mediator_tcp_from_port},
        state.direction
      )

    {:ok, port, os_pid} = Exec.capture_std_mon(cmd)

    case state.direction do
      :reverse ->
        {:ok, _} =
          PortRelay.start_link_now(
            state.auth,
            state.remote,
            state.from_port,
            :udp,
            mediator_tcp_from_port,
            :tcp
          )

        {:ok, _} =
          PortRelay.start_link_now(mediator_tcp_to_port, :tcp, state.to_spot.port, :udp)

      :forward ->
        {:ok, _} =
          PortRelay.start_link_now(state.from_port, :udp, mediator_tcp_from_port, :tcp)

        {:ok, _} =
          PortRelay.start_link_now(
            state.auth,
            state.remote,
            mediator_tcp_to_port,
            :tcp,
            state.to_spot.port,
            :udp
          )
    end

    {:reply, :ok,
     %{
       state
       | ssh_tunnel_port: port,
         os_pid: os_pid,
         mediator_tcp_from_port: mediator_tcp_from_port,
         mediator_tcp_to_port: mediator_tcp_to_port,
         status: :connected
     }}
  end

  @impl true
  def handle_info({port, {:data, _data}}, %{ssh_tunnel_port: port} = state) do
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _status}}, %{ssh_tunnel_port: port} = state) do
    {:stop, :tunnel_exited, state}
  end

  @impl true
  def terminate(_reason, %{os_pid: os_pid}) when is_integer(os_pid) do
    System.cmd("kill", [to_string(os_pid)])
    :ok
  rescue
    _ -> :ok
  end

  def terminate(_reason, _state), do: :ok
end
