defmodule Fusion.ConnectorExternalTest do
  use ExUnit.Case

  alias Fusion.Connector
  alias Fusion.Test.Helpers.Assert
  alias Fusion.Test.Helpers.Docker

  setup_all _context do
    Application.ensure_started(:dockerex)
    HTTPoison.start # dockerex dependecy
    :ok
  end

  setup _context do                      
    {:ok, _} = Node.start(:"master@localhost", :shortnames)

    %{ container_id: container_id, server: server, auth: auth } = 
      Docker.init_docker_container("fusion_tester")

    Process.sleep(1000)                 

    on_exit fn ->                       
      Node.stop()
      Process.sleep(500)                
      Docker.remove_docker_container(container_id)
    end 
        
    {:ok, [auth: auth, server: server, container_id: container_id, ]} 
  end

  @tag timeout: 1500000
  test "start a connector successfuly", context do
    {:ok, connector} = Connector.start_link_now(context[:auth], context[:server])

    Process.sleep(154000)

    origin_node_tunnel = Connector.get_origin_node_tunnel(connector)
    Assert.assert_remote_port_up(context[:auth], context[:server], origin_node_tunnel.from_port)

    remote_node_tunnel = Connector.get_remote_node_tunnel(connector)
    Assert.assert_local_port_up(remote_node_tunnel.from_port)

    remote_node = Connector.get_remote_node(connector)
    Assert.assert_remote_port_up(context[:auth], context[:server], remote_node.port)

    origin_epmd_tunnel = Connector.get_origin_epmd_tunnel(connector)
    Assert.assert_remote_port_up(context[:auth], context[:server], origin_epmd_tunnel.from_port)

    boot_server_discovery_tunnel = Connector.get_boot_server_discovery_tunnel(connector)
    Assert.assert_remote_port_up(context[:auth], context[:server], 
                                 boot_server_discovery_tunnel.from_port)

    remote_prim_loader_discoverer_tunnel = 
      Connector.get_remote_prim_loader_discoverer_tunnel(connector)
    Assert.assert_local_port_up(remote_prim_loader_discoverer_tunnel.from_port)
    Assert.assert_remote_port_up(
      context[:auth], context[:server], remote_prim_loader_discoverer_tunnel.to_spot.port)

    boot_server_tunnel = Connector.get_boot_server_tunnel(connector)
    Assert.assert_remote_port_up(context[:auth], context[:server], boot_server_tunnel.from_port)
  end
end
