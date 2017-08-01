defmodule Fusion.UdpTunnel do
  @moduledoc """
  A GenServer for handling of opening udp tunnel network and observing their state.
  """
  alias Fusion.UdpTunnel
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot
  alias Fusion.Net
  alias Fusion.PortRelay

  defstruct status: :off,
    ssh_tunnel_pid: nil,
    auth: nil,
    remote: nil,
    direction: nil,
    from_port: nil,
    to_spot: nil,
    mediator_tcp_from_port: nil,
    mediator_tcp_to_port: nil,
    allow_connection_refused: false

  use GenServer
  require Logger

  def start_link(auth, remote, direction, from_port, to_spot, args \\ []) do
    GenServer.start_link(__MODULE__, [auth, remote, direction, from_port, to_spot, args], [])
  end

  def start_link_now(auth, remote, direction, from_port, to_spot, args \\ []) do
    {:ok, server} = res = start_link(auth, remote, direction, from_port, to_spot, args)
    :ok = start_tunnel(server)
    res
  end

  def start_tunnel(server) do
    GenServer.call(server, {:start_tunnel})
  end

  ## Server Callbacks
  
  def init([auth, remote, direction, from_port, to_spot, args]) do
    {:ok, %UdpTunnel{
      auth: auth,
      remote: remote,
      direction: direction,
      from_port: from_port,
      to_spot: to_spot,
      allow_connection_refused: Keyword.get(args, :allow_connection_refused, false)
    }}
  end

  def handle_call({:start_tunnel}, _from, %UdpTunnel{status: :off} = state) do
    mediator_tcp_from_port = Net.gen_port()
    mediator_tcp_to_port = mediator_tcp_from_port

    {:ok, tunnel_pid, _os_pid} = Ssh.cmd_port_tunnel(
      state.auth, state.remote, mediator_tcp_from_port, 
      %Spot{host: "localhost", port: mediator_tcp_from_port}, 
      state.direction)
    |> Exec.capture_std_mon

    case state.direction do
      :reverse ->
        {:ok, _} = PortRelay.start_link_now(
          state.auth, state.remote, state.from_port, :udp, mediator_tcp_from_port, :tcp)
        {:ok, _} = PortRelay.start_link_now(
          mediator_tcp_to_port, :tcp, state.to_spot.port, :udp,
          allow_connection_refused: state.allow_connection_refused
        )
      :forward ->
        {:ok, _} = PortRelay.start_link_now(state.from_port, :udp, mediator_tcp_from_port, :tcp)
        {:ok, _} = PortRelay.start_link_now(
          state.auth, state.remote, mediator_tcp_to_port, :tcp, state.to_spot.port, :udp,
          allow_connection_refused: state.allow_connection_refused
        )
    end

    {:reply, :ok, %{ state | 
      ssh_tunnel_pid: tunnel_pid, 
      mediator_tcp_from_port: mediator_tcp_from_port,
      mediator_tcp_to_port: mediator_tcp_to_port,
      status: :after_connect_trial
    }}
  end

	def handle_info({:stdout, _proc_id, msg}, state) do
		Logger.debug "stdout"
		IO.inspect msg

    # todo
    {:noreply, state}
  end

  def handle_info({:stderr, _proc_id, _msg}, state) do
    cond do
      true ->
        {:stop, :stderr, state}
    end
  end
end
