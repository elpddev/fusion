defmodule Fusion.Connector do
  @moduledoc """                        
    A GenServer for handling of opening a connection to a remote server and establishing the remote worker.
    """

  use GenServer

  @eboot_port 4368 

  alias Fusion.Connector
  alias Fusion.Net.Spot
  alias Fusion.Net.ErlNode
  alias Fusion.Net
  alias Fusion.SshPortTunnel
  alias Fusion.UdpTunnel
  alias Fusion.ErlBootServerAnalyzer, as: Analyzer
  alias Fusion.Utilities.Erl
  alias Fusion.Utilities.Ssh

  defstruct auth: nil,
    remote: nil,
    status: :off,
    origin_node: nil,
    origin_node_tunnel: nil,
    epmd_port: nil,
    origin_epmd_tunnel: nil,
    remote_node: nil,
    remote_node_tunnel: nil,
    boot_server_discovery_port: nil,
    boot_server_discovery_tunnel: nil,
    boot_server_analyzer: nil,
    remote_prim_loader_discoverer_port: nil,
    remote_prim_loader_discoverer_tunnel: nil,
    boot_server_port: nil,
    boot_server_tunnel: nil

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
    GenServer.cast(server, {:start_connector})
  end 

	## Server Callbacks		

	def init([auth, remote]) do
    case Node.alive? do
      false -> 
        {:stop, :original_node_is_not_alive}
      true ->
        {:ok, %Connector{
          auth: auth,
          remote: remote,
          status: :off,
        }}
    end
  end

  def handle_cast({:start_connector}, _, %Connector{
    auth: auth, 
    remote: remote, 
    status: :off
  } = state) do

    origin_node = Net.get_erl_node()
    {:ok, origin_node_tunnel} = open_tunnel_for_origin_node(auth, remote, origin_node)
    epmd_port = Net.get_epmd_port()
    {:ok, origin_epmd_tunnel} = open_tunnel_for_origin_epmd(auth, remote, epmd_port)
    {:ok, remote_node} = gen_remote_node_info(auth, remote, origin_node)
    {:ok, remote_node_tunnel} = open_tunnel_for_remote_node(auth, remote, remote_node) 
    boot_server_discovery_port = @eboot_port
    {:ok, boot_server_analyzer} = start_boot_server_analyzer(boot_server_discovery_port)
    {:ok, boot_server_discovery_tunnel} = open_boot_server_discovery_tunnel(
      auth, remote, boot_server_discovery_port) 
    :ok = start_remote_node(auth, remote, remote_node, origin_epmd_tunnel.from_port) 

    {:noreply, %Connector{state |
      origin_node: origin_node,
      origin_node_tunnel: origin_node_tunnel,
      epmd_port: epmd_port,
      origin_epmd_tunnel: origin_epmd_tunnel,
      remote_node: remote_node,
      remote_node_tunnel: remote_node_tunnel,
      boot_server_discovery_port: boot_server_discovery_port,
      boot_server_discovery_tunnel: boot_server_discovery_tunnel,
      boot_server_analyzer: boot_server_analyzer,
      status: :waiting_remote_prim_loader_contact
    }}
  end

  def handle_info(
    {:incoming_udp_contact_req, {127, 0, 0, 1}, remote_prim_loader_discoverer_port}, 
    %Connector{ status: :waiting_remote_prim_loader_contact, } = state) do

    Process.send(self(), {:start_connector}, []) 

    {:noreply, %Connector{state | 
      remote_prim_loader_discoverer_port: remote_prim_loader_discoverer_port,
      status: :received_remote_prim_loader_contact
    }}
  end

  def handle_info({:start_connector}, %Connector{
    auth: auth, 
    remote: remote,
    status: :received_remote_prim_loader_contact
  } = state) do

    GenServer.stop(state.boot_server_analyzer)

    {:ok, remote_prim_loader_discoverer_tunnel} = start_tunnel_remote_prim_loader_discoverer(
      auth, remote, state.remote_prom_loader_discoverer_port) 
    {:ok, boot_server_port} = start_boot_server(state.boot_server_discovery_port)
    {:ok, boot_server_tunnel} = start_boot_server_tunnel(auth, remote, boot_server_port)
    :ok = connect_remote_node(state.remote_node)
    :ok = load_paths_on_remote_node(state.remote_node)

    {:noreply, %Connector{state | 
      remote_prim_loader_discoverer_tunnel: remote_prim_loader_discoverer_tunnel,
      boot_server_port: boot_server_port,
      boot_server_tunnel: boot_server_tunnel,
    }}
  end

  def open_tunnel_for_origin_node(auth, remote, %ErlNode{} = origin_node) do
    from_port = origin_node.port
    to_spot = %Spot{host: "localhost", port: origin_node.port}

    {:ok, tunnel_pid} = SshPortTunnel.start_link_now(auth, remote, :reverse, from_port, to_spot)

    {:ok, %{
      from_port: origin_node.port,
      to_spot: to_spot,
      direction: :reverse,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def open_tunnel_for_origin_epmd(auth, remote, epmd_local_port) do
    from_port = epmd_local_port
    to_spot = %Spot{host: "localhost", port: epmd_local_port}

    {:ok, tunnel_pid} = SshPortTunnel.start_link_now(
      auth, remote, :reverse, from_port, to_spot)

    {:ok, %{
      from_port: from_port,
      to_spot: to_spot,
      direction: :reverse,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def gen_remote_node_info(_auth, _remote, origin_node) do
    {:ok, %ErlNode{
      port: Net.gen_port(),
      name: "worker",
      host: origin_node.host,
      cookie: origin_node.cookie,
    }}
  end

  def open_tunnel_for_remote_node(auth, remote, remote_node) do
    from_port = remote_node.port
    to_spot = %Spot{host: "localhost", port: remote_node.port}

    {:ok, tunnel_pid} = SshPortTunnel.start_link_now(
      auth, remote, :forward, from_port, to_spot)

    {:ok, %{
      from_port: from_port,
      to_spot: to_spot,
      direction: :forward,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def start_boot_server_analyzer(_boot_server_discovery_port) do
    {:ok, analyzer} = Analyzer.start_link_now()
    Analyzer.register_for_incoming_req(analyzer)

    {:ok, analyzer}
  end

  def open_boot_server_discovery_tunnel(auth, remote, boot_server_discovery_port) do
    from_port = boot_server_discovery_port 
    to_spot = %Spot{host: "localhost", port: boot_server_discovery_port}

    {:ok, tunnel_pid} = UdpTunnel.start_link_now(
      auth, remote, :reverse, 
      from_port,
      to_spot)

    {:ok, %{
      from_port: from_port,
      to_spot: to_spot,
      direction: :reverse,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def start_remote_node(auth, remote, remote_node, epmd_port) do
    {:ok, _pid, _osid} = 
      Erl.cmd_erl_inet_loader(remote_node, epmd_port)
      |> Ssh.cmd_remote(auth, remote)
      |> String.to_char_list 
      |> :exec.run([:stdout, :stderr])

    :ok
  end

  def start_tunnel_remote_prim_loader_discoverer(auth, remote, discoverer_port) do
    from_port = discoverer_port
    to_spot = %Spot{host: "localhost", port: discoverer_port} 

    {:ok, tunnel_pid} = UdpTunnel.start_link_now(
      auth, remote, :forward, 
      from_port,
      to_spot) 

    {:ok, %{
      from_port: from_port,
      to_spot: to_spot,
      direction: :forward,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def start_boot_server(_discovery_port) do
    {:ok, boot_server} = :erl_boot_server.start([{127, 0, 0, 1}])

    Process.sleep(500)

    #todo: how to choose/inspect and get erl_boot_manager tcp port
    {:state, 
      _priority, _version, _udp_sock, _udp_port, _listen_sock, listen_port, 
      _slaves, _bootp, _prim_state
    } = :sys.get_state(boot_server)

    {:ok, listen_port}
  end

  def start_boot_server_tunnel(auth, remote, boot_server_port) do
    from_port = boot_server_port
    to_spot = %{host: "localhost", port: boot_server_port}

    {:ok, tunnel_pid} = SshPortTunnel.start_link_now(
      auth, remote, :reverse, from_port, to_spot)

    {:ok, %{
      from_port: from_port,
      to_spot: to_spot,
      direction: :reverse,
      remote: remote, 
      tunnel_pid: tunnel_pid
    }}
  end

  def connect_remote_node(%ErlNode{} = remote_node) do
    true = 
      :"#{remote_node.name}@#{remote_node.host}"
      |> Node.connect()

    :ok
  end

  def load_paths_on_remote_node(%ErlNode{} = remote_node) do
    paths = :code.get_path()

    :"#{remote_node.name}@#{remote_node.host}"
    |> Node.spawn_link(fn -> 
        :ok = :code.add_paths(paths)
      end)

    :ok
  end
end
