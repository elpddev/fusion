defmodule Fusion.Connector do
  @moduledoc """                        
    A GenServer for handling of opening a connection to a remote server and establishing the remote worker.
    """

  use GenServer

  alias Fusion.Connector
  alias Fusion.Net.Spot
  alias Fusion.Net.ErlNode
  alias Fusion.Net
  alias Fusion.SshPortTunnel

  defstruct auth: nil,
    remote: nil,
    origin_node: nil,
    remote_node: nil,
    epmd_port: nil,
		epmd_remote_port: nil

	## Public interface

  def start_link(auth, remote) do       
    GenServer.start_link(__MODULE__, [auth, remote], [])
  end
      
  def start_link_now(auth, remote) do   
    {:ok, server} = res = start_link(auth, remote)
    :ok = start_connector(server)    
    res 
  end

  def start_connector(server) do        
    GenServer.call(server, {:start_connector})
  end 

  def get_origin_node(server) do
    GenServer.call(server, {:get_origin_node})
  end

  def get_remote_node(server) do
    GenServer.call(server, {:get_remote_node})
  end

  def get_epmd_remote_port(server) do
    GenServer.call(server, {:get_epmd_remote_port})
  end

	## Server Callbacks		

	def init([auth, remote]) do
    case Node.alive? do
      false -> 
        {:stop, :original_node_is_not_alive}
      true ->
        {:ok, %Connector{
          auth: auth,
          remote: remote
        }}
    end
  end

  def handle_call({:start_connector}, _, state) do
    do_start_connector(state) 
  end

  def handle_call({:get_origin_node}, _, %Connector{} = state) do
    {:reply, state.origin_node, state}
  end

  def handle_call({:get_remote_node}, _, %Connector{} = state) do
    {:reply, state.remote_node, state}
  end

  def handle_call({:get_epmd_remote_port}, _, %Connector{} = state) do
    {:reply, state.epmd_remote_port, state}
  end

  def do_start_connector(%Connector{auth: auth, remote: remote} = state) do
    origin_node = Net.get_erl_node() 
    remote_node = gen_remote_node_info(origin_node.host, origin_node.cookie)
    epmd_port = Net.get_epmd_port()
    epmd_remote_port = Net.gen_port()

    open_tunnel_for_origin_node!(
      auth, remote, origin_node.port, %Spot{host: "localhost", port: origin_node.port})
    open_tunnel_for_remote_node!(
      auth, remote, remote_node.port, %Spot{host: "localhost", port: remote_node.port})
    open_tunnel_for_origin_epmd!(
      auth, remote, epmd_remote_port, %Spot{host: "localhost", port: epmd_port})

    {:reply, :ok, %Connector{state | 
      origin_node: origin_node,
      remote_node: remote_node,
      epmd_port: epmd_port,
      epmd_remote_port: epmd_remote_port
    }}
  end

  def open_tunnel_for_origin_node!(
    auth, %Spot{} = remote, origin_remote_port, %Spot{} = origin_local_spot) do

    {:ok, _} = SshPortTunnel.start_link_now(
      auth, remote, :reverse, origin_remote_port, origin_local_spot)
  end

  def open_tunnel_for_remote_node!(
    auth, %Spot{} = remote, node_local_port, %Spot{} = node_remote_spot) do

    {:ok, _} = SshPortTunnel.start_link_now(
      auth, remote, :forward, node_local_port, node_remote_spot)
  end

  def open_tunnel_for_origin_epmd!(
    auth, %Spot{} = remote, epmd_remote_entrance, epmd_local_exit) do

    {:ok, _} = SshPortTunnel.start_link_now(
      auth, remote, :reverse, epmd_remote_entrance, epmd_local_exit)
  end

  def gen_remote_node_info(host, cookie) do
    port = Net.gen_port()

    %ErlNode{
      port: port,
      host: host,
      cookie: cookie
    }
  end
end
