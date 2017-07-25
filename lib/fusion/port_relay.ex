defmodule Fusion.PortRelay do
  @moduledoc """
  A GenServer for making a connection between two different ports udp/tcp. Using socat.
  """

  use GenServer
	require Logger

  alias Fusion.PortRelay
  alias Fusion.Utilities.Socat
  alias Fusion.Utilities.Exec

  defstruct status: :off,
    from_port: nil,
    from_type: nil,
    to_port: nil,
    to_type: nil,
    relay_pid: nil

  def start_link(from_port, from_type, to_port, to_type) do
    GenServer.start_link(__MODULE__, [from_port, from_type, to_port, to_type], [])
  end

  def start_link_now(from_port, from_type, to_port, to_type) do
    {:ok, server} = res = start_link(from_port, from_type, to_port, to_type)
    :ok = start_tunnel(server) 
    res
  end

  def start(from_port, from_type, to_port, to_type) do
    GenServer.start(__MODULE__, [from_port, from_type, to_port, to_type], [])
  end

  def start_now(from_port, from_type, to_port, to_type) do
    {:ok, server} = res = start(from_port, from_type, to_port, to_type)
    :ok = start_tunnel(server) 
    res
  end
  
  def start_tunnel(server) do
    GenServer.call(server, {:start_tunnel})
  end

  ## Server Callbacks
  
  def init([from_port, from_type, to_port, to_type]) do
    {:ok, %PortRelay{
      from_port: from_port,
      from_type: from_type,
      to_port: to_port,
      to_type: to_type
    }}
  end

  def handle_call({:start_tunnel}, _from, %PortRelay{} = state) do
    cmd_str = <<x :: binary>> = Socat.cmd(
      state.from_port, state.from_type, state.to_port, state.to_type)
    {:ok, relay_pid, _os_pid} = cmd_str |> Exec.capture_std_mon

    {:reply, :ok, %PortRelay{state | relay_pid: relay_pid }}
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

  def handle_info({:DOWN, _os_id, :process, _pid, _status}, state) do
    {:stop, :error_termination_in_exec_process, state}
  end

end
