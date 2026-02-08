defmodule Fusion.PortRelay do
  @moduledoc "GenServer for bridging between UDP/TCP ports using socat."

  use GenServer
  require Logger

  alias Fusion.Utilities.Socat
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Bash

  defstruct status: :off,
            from_port: nil,
            from_type: nil,
            to_port: nil,
            to_type: nil,
            relay_port: nil,
            os_pid: nil,
            auth: nil,
            remote: nil,
            location: nil

  ## Public API

  def start_link(from_port, from_type, to_port, to_type) do
    GenServer.start_link(__MODULE__, [nil, nil, :local, from_port, from_type, to_port, to_type])
  end

  def start_link(auth, remote, from_port, from_type, to_port, to_type) do
    GenServer.start_link(__MODULE__, [
      auth,
      remote,
      :remote,
      from_port,
      from_type,
      to_port,
      to_type
    ])
  end

  def start_link_now(from_port, from_type, to_port, to_type) do
    {:ok, server} = res = start_link(from_port, from_type, to_port, to_type)
    :ok = start_tunnel(server)
    res
  end

  def start_link_now(auth, remote, from_port, from_type, to_port, to_type) do
    {:ok, server} = res = start_link(auth, remote, from_port, from_type, to_port, to_type)
    :ok = start_tunnel(server)
    res
  end

  def start_tunnel(server) do
    GenServer.call(server, :start_tunnel)
  end

  ## Callbacks

  @impl true
  def init([auth, remote, location, from_port, from_type, to_port, to_type]) do
    {:ok,
     %__MODULE__{
       from_port: from_port,
       from_type: from_type,
       to_port: to_port,
       to_type: to_type,
       auth: auth,
       remote: remote,
       location: location
     }}
  end

  @impl true
  def handle_call(:start_tunnel, _from, %__MODULE__{location: :local} = state) do
    cmd_str = Socat.cmd(state.from_port, state.from_type, state.to_port, state.to_type)
    {:ok, port, os_pid} = Exec.capture_std_mon(cmd_str)

    {:reply, :ok, %{state | relay_port: port, os_pid: os_pid, status: :connected}}
  end

  def handle_call(:start_tunnel, _from, %__MODULE__{location: :remote} = state) do
    socat_cmd_str = Socat.cmd(state.from_port, state.from_type, state.to_port, state.to_type)

    cmd_str =
      Ssh.cmd("", state.auth, state.remote) <>
        " \"#{Bash.escape_str(socat_cmd_str)}\""

    {:ok, port, os_pid} = Exec.capture_std_mon(cmd_str)

    {:reply, :ok, %{state | relay_port: port, os_pid: os_pid, status: :connected}}
  end

  @impl true
  def handle_info({port, {:data, _data}}, %{relay_port: port} = state) do
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _status}}, %{relay_port: port} = state) do
    {:stop, :relay_exited, state}
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
