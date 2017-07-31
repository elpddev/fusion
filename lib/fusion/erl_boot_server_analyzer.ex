defmodule Fusion.ErlBootServerAnalyzer do
  @moduledoc """
  An helper genserver to catch erl_prim_loader initial contact discovery requests.
  """

  use GenServer
	require Logger

  alias Fusion.ErlBootServerAnalyzer, as: Analyzer

  # https://github.com/erlang/otp/blob/1526eaead833b3bdcd3555a12e2af62c359e7868/lib/kernel/src/inet_boot.hrl
  @eboot_port 4368 

  # https://github.com/erlang/otp/blob/1526eaead833b3bdcd3555a12e2af62c359e7868/lib/kernel/src/inet_boot.hrl
  @eboot_request 'EBOOTQ'

  @erl_version :erlang.system_info(:version)
  @contact_req_token (@eboot_request ++ @erl_version)
  @contact_req_token_str (@contact_req_token |> List.to_string)

  defstruct status: :off,
    discovery_port: nil,
    udp_listener: nil,
    erl_version: nil,
    contact_req_token: nil,
    incoming_req_listener: nil

	## Public interface

  def start_link() do       
    GenServer.start_link(__MODULE__, [], [])
  end

  def start_link_now() do       
    {:ok, server} = res = GenServer.start_link(__MODULE__, [], [])
    :ok = start_server(server)
    res
  end

  def start_server(server) do
    GenServer.call(server, {:start})
  end

  def register_for_incoming_req(server) do
    GenServer.call(server, {:register_for_incoming_req, self()})
  end

  def get_discovery_port(server) do
    GenServer.call(server, {:get_discovery_port})
  end

  ## Server Callbacks
  
  def init([]) do
    {:ok, %Analyzer{
      status: :off,
      discovery_port: @eboot_port,
      erl_version: @erl_version,
      contact_req_token: @contact_req_token,
    }}
  end
  
  def handle_call({:start}, _from, %Analyzer{status: :off} = state) do
    udp_listener = Socket.UDP.open!(state.discovery_port, mode: :active)

    {:reply, :ok, %Analyzer{state | udp_listener: udp_listener}}
  end

  def handle_call({:register_for_incoming_req, listener}, _from, state) do
    {:reply, :ok, %Analyzer{state | incoming_req_listener: listener}}
  end

  def handle_call({:get_discovery_port}, _from, %Analyzer{discovery_port: discovery_port} = state) do
    {:reply, discovery_port, state}
  end

  def handle_info({:udp, _udp_listener, sender_ip, sender_port, @contact_req_token_str}, state) do
    case state.incoming_req_listener do
      nil -> 
        :ok
      reg_listener -> 
        Process.send(reg_listener, {:incoming_udp_contact_req, sender_ip, sender_port}, [])
    end

    {:noreply, state}
  end

  def handle_info({:udp, _udp_listener, _sender_ip, _sender_port, packet}, state) do
    # todo
    Logger.debug("incomming udp msg")
    Logger.debug(packet)

    {:noreply, state}
  end
end
