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
    %{ container_id: container_id, server: server, auth: auth } = 
      Docker.init_docker_container("fusion_tester")

    Node.start(:"master@localhost", :shortnames)
    Process.sleep(1000)                 

    on_exit fn ->                       
      Node.stop()
      Process.sleep(500)                
      Docker.remove_docker_container(container_id)
    end 
        
    {:ok, [auth: auth, server: server, container_id: container_id, ]} 
  end

  test "start a connector successfuly", context do
    {:ok, connector} = Connector.start_link_now(context[:auth], context[:server])

    origin_node = Connector.get_origin_node(connector)
    remote_node = Connector.get_remote_node(connector)

    Assert.assert_remote_port_up(context[:auth], context[:server], origin_node.port)
    Assert.assert_local_port_up(remote_node.port)
  end
end
