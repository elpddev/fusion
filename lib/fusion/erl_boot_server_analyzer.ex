defmodule Fusion.ErlBootServerAnalyzer do
  @moduledoc "GenServer that catches erl_prim_loader initial contact discovery requests."

  use GenServer
  require Logger

  @eboot_port 4368
  @eboot_request ~c"EBOOTQ"
  @erl_version :erlang.system_info(:version)
  @contact_req_token @eboot_request ++ @erl_version
  @contact_req_token_str List.to_string(@contact_req_token)

  defstruct status: :off,
            udp_port: nil,
            udp_socket: nil,
            erl_version: nil,
            contact_req_token: nil,
            incoming_req_listener: nil

  ## Public API

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def start_link_now do
    {:ok, server} = res = start_link()
    :ok = start_server(server)
    res
  end

  def start_server(server) do
    GenServer.call(server, :start)
  end

  def register_for_incoming_req(server) do
    GenServer.call(server, {:register_for_incoming_req, self()})
  end

  ## Callbacks

  @impl true
  def init([]) do
    {:ok,
     %__MODULE__{
       status: :off,
       udp_port: @eboot_port,
       erl_version: @erl_version,
       contact_req_token: @contact_req_token
     }}
  end

  @impl true
  def handle_call(:start, _from, %__MODULE__{status: :off} = state) do
    {:ok, socket} = :gen_udp.open(state.udp_port, [:binary, active: true])
    {:reply, :ok, %{state | udp_socket: socket, status: :listening}}
  end

  def handle_call({:register_for_incoming_req, listener}, _from, state) do
    {:reply, :ok, %{state | incoming_req_listener: listener}}
  end

  @impl true
  def handle_info({:udp, _socket, sender_ip, sender_port, @contact_req_token_str}, state) do
    case state.incoming_req_listener do
      nil -> :ok
      listener -> send(listener, {:incoming_udp_contact_req, sender_ip, sender_port})
    end

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _sender_ip, _sender_port, _packet}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{udp_socket: socket}) when not is_nil(socket) do
    :gen_udp.close(socket)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
