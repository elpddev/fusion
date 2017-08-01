defmodule Fusion.PortRelay do
  @moduledoc """
  A GenServer for making a connection between two different ports udp/tcp. Using socat.
  """

  use GenServer
	require Logger

  @socat_conn_refused_err_regex ~r/.*socat.*: Connection refused.*/

  alias Fusion.PortRelay
  alias Fusion.Utilities.Socat
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Bash

  defstruct status: :off,
    from_port: nil,
    from_type: nil,
    to_port: nil,
    to_type: nil,
    relay_pid: nil,
    auth: nil,
    remote: nil,
    location: nil,
    allow_connection_refused: false

  def start_link(from_port, from_type, to_port, to_type, args \\ []) do
    GenServer.start_link(__MODULE__, [nil, nil, :local, from_port, from_type, to_port, to_type, args], [])
  end

  def start_link(auth, remote, from_port, from_type, to_port, to_type, args \\ []) do
    GenServer.start_link(
      __MODULE__, [auth, remote, :remote, from_port, from_type, to_port, to_type, args], [])
  end

  def start_link_now(from_port, from_type, to_port, to_type, args \\ []) do
    {:ok, server} = res = start_link(from_port, from_type, to_port, to_type, args)
    :ok = start_tunnel(server) 
    res
  end
  
  def start_link_now(auth, remote, from_port, from_type, to_port, to_type, args \\ []) do
    {:ok, server} = res = start_link(auth, remote, from_port, from_type, to_port, to_type, args)
    :ok = start_tunnel(server) 
    res
  end

  def start(from_port, from_type, to_port, to_type, args \\ []) do
    GenServer.start(__MODULE__, [nil, nil, :local, from_port, from_type, to_port, to_type, args], [])
  end

  def start(auth, remote, from_port, from_type, to_port, to_type, args \\ []) do
    GenServer.start(__MODULE__, [auth, remote, :remote, from_port, from_type, to_port, to_type, args], [])
  end

  def start_now(from_port, from_type, to_port, to_type, args \\ []) do
    {:ok, server} = res = start(from_port, from_type, to_port, to_type, args)
    :ok = start_tunnel(server) 
    res
  end

  def start_now(auth, remote, from_port, from_type, to_port, to_type, args \\ []) do
    {:ok, server} = res = start(auth, remote, from_port, from_type, to_port, to_type, args)
    :ok = start_tunnel(server) 
    res
  end
  
  def start_tunnel(server) do
    GenServer.call(server, {:start_tunnel})
  end

  ## Server Callbacks
  
  def init([auth, remote, location, from_port, from_type, to_port, to_type, args]) do
    {:ok, %PortRelay{
      from_port: from_port,
      from_type: from_type,
      to_port: to_port,
      to_type: to_type,
      auth: auth,
      remote: remote,
      location: location,
      allow_connection_refused: Keyword.get(args, :allow_connection_refused, false)
    }}
  end

  def handle_call({:start_tunnel}, _from, %PortRelay{location: :local} = state) do
    cmd_str = <<_x :: binary>> = Socat.cmd(
      state.from_port, state.from_type, state.to_port, state.to_type)
    {:ok, relay_pid, _os_pid} = cmd_str |> Exec.capture_std_mon

    {:reply, :ok, %PortRelay{state | relay_pid: relay_pid }}
  end

  def handle_call({:start_tunnel}, _from, %PortRelay{location: :remote} = state) do
    socat_cmd_str = <<_x :: binary>> = Socat.cmd(
      state.from_port, state.from_type, state.to_port, state.to_type)

    cmd_str = Ssh.cmd("", state.auth, state.remote) <> " " <> 
      "\"#{socat_cmd_str |> Bash.escape_str()}\""

    {:ok, relay_pid, _os_pid} = cmd_str |> Exec.capture_std_mon

    {:reply, :ok, %PortRelay{state | relay_pid: relay_pid }}
  end

	def handle_info({:stdout, _proc_id, msg}, state) do
		Logger.debug "stdout"
		IO.inspect msg

    # todo
    {:noreply, state}
  end

  def handle_info({:stderr, _proc_id, msg}, state) do
    cond do
      Regex.match?(@socat_conn_refused_err_regex, msg) ->
        case state.allow_connection_refused do
          true -> {:noreply, state}
          _ -> {:stop, :connection_refused_in_tunnel, state}
        end
      true ->
        {:stop, {:stderr, msg}, state}
    end
  end

  def handle_info({:DOWN, _os_id, :process, _pid, _status}, state) do
    {:stop, :error_termination_in_exec_process, state}
  end

end
