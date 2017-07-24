defmodule Fusion.SshPortTunnel do
  @moduledoc """
  A GenServer for handling of opening ssh ports tunnels and observing their state.
  """

  use GenServer
	require Logger

  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Ssh
  alias Fusion.SshPortTunnel

  @conn_refused_err_regex ~r/ssh: connect to host.*Connection refused.*/
  @cannot_assign_requested_address_regex ~r/bind: Cannot assign requested address.*/

  defstruct auth: nil,
    remote: nil,
    direction: nil,
    from_port: nil,
    to_spot: nil,
    status: :off,
    ssh_tunnel_pid: nil

  def start_link(auth, remote, direction, from_port, to_spot) do
    GenServer.start_link(__MODULE__, 
     [auth, remote, direction, from_port, to_spot], [])
  end

  def start_link_now(auth, remote, direction, from_port, to_spot) do
    {:ok, server} = res = start_link(
      auth, remote, direction, from_port, to_spot)
    :ok = start_tunnel(server)
    res 
  end

  def start(auth, remote, direction, from_port, to_spot) do
    GenServer.start(__MODULE__, 
     [auth, remote, direction, from_port, to_spot], [])
  end

  def start_now(auth, remote, direction, from_port, to_spot) do
    {:ok, server} = res = start(
      auth, remote, direction, from_port, to_spot)
    :ok = start_tunnel(server)
    res 
  end

  def start_tunnel(server) do
    GenServer.call(server, {:start_tunnel})
  end

  ## Server Callbacks
  
  def init([auth, remote, direction, from_port, to_spot]) do
    {:ok, %SshPortTunnel{ 
      auth: auth, 
      remote: remote, 
      direction: direction,
      from_port: from_port, 
      to_spot: to_spot,
    }}
  end

  def handle_call({:start_tunnel}, _from, 
    %SshPortTunnel{status: :off} = state) do

    {:ok, tunnel_pid, _os_pid} = 
      Ssh.cmd_port_tunnel(
        state.auth, state.remote, state.from_port, state.to_spot, 
        state.direction)
    |> Exec.capture_std_mon

    {:reply, :ok, %{ state | ssh_tunnel_pid: tunnel_pid, 
      status: :after_connect_trial}}
  end

	def handle_info({:stdout, _proc_id, msg}, state) do
		Logger.debug "stdout"
		IO.inspect msg

    # todo
    {:noreply, state}
  end

  def handle_info({:stderr, _proc_id, msg}, state) do
    cond do
      Regex.match?(@conn_refused_err_regex, msg) ->
        {:stop, :conn_refused, state}
      Regex.match?(@cannot_assign_requested_address_regex, msg) ->
        {:stop, :address_binding_failure, state}
      true ->
        {:stop, :stderr, state}
    end
  end

  def handle_info({:DOWN, _os_id, :process, _pid, _status}, state) do
    {:stop, :error_termination_in_exec_process, state}
  end

end
