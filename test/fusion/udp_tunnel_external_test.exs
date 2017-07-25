defmodule Fusion.UdpTunnelExternalTest do
  use ExUnit.Case

  alias Fusion.Test.Helpers.Docker
  alias Fusion.UdpTunnel
  #alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot
  alias Fusion.Net

  setup_all _context do
    Application.ensure_started(:dockerex)
    HTTPoison.start # dockerex dependecy
    :ok
  end

  setup _context do                      
    %{ container_id: container_id, server: server, auth: auth } = 
      Docker.init_docker_container("fusion_tester")

    Process.sleep(1000)                 

    on_exit fn ->                       
      Process.sleep(500)                
      Docker.remove_docker_container(container_id)
    end 
        
    {:ok, [ auth: auth, server: server, container_id: container_id, ]} 
  end

  test "open reverse udp tunnel with success", context do
    origin_port = Net.gen_port()
    remote_port = Net.gen_port()

    {:ok, _} = UdpTunnel.start_link_now(
      context[:auth], context[:server], 
      :reverse, 
      remote_port,
      %Spot{host: "localhost", port: origin_port}
    ) 
  end
end
