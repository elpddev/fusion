defmodule Fusion.UdpTunnelExternalTest do
  use ExUnit.Case

  alias Fusion.Test.Helpers.Docker
  alias Fusion.UdpTunnel
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Bash
  alias Fusion.Utilities.Netcat
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Socat
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
        
    {:ok, [ auth: auth, server: server, container_id: container_id ]} 
  end

  test "open reverse udp tunnel with success", context do
    origin_port = Net.gen_port()
    remote_port = Net.gen_port()
    msg = "hello"
    expected_msg = "#{msg}"

    {:ok, _} = UdpTunnel.start_link_now(
      context[:auth], context[:server], 
      :reverse, 
      remote_port,
      %Spot{host: "localhost", port: origin_port}
    ) 

    Process.sleep(1000)

    udp_server = Socket.UDP.open!(origin_port)

    Ssh.cmd("", context[:auth], context[:server]) <> " " <>  
		"\"#{(Netcat.cmd_send_udp_message("localhost", remote_port, msg) |> Bash.escape_str())}\""
    |> Exec.run_sync_printall

    {:ok, {^expected_msg, _client}} = udp_server |> Socket.Datagram.recv(timeout: 2000)
  end

  test "open forward udp tunnel with success", context do
    origin_port = Net.gen_port()
    remote_port = Net.gen_port()
    msg = "hello"
    expected_msg = "#{msg}\r\n"

    {:ok, _} = UdpTunnel.start_link_now(
      context[:auth], context[:server], 
      :forward, 
      origin_port,
      %Spot{host: "localhost", port: remote_port}
    ) 

    Process.sleep(1000)

    {:ok, _, _} = 
      Socat.cmd_udp_echo_server(remote_port)
      |> Ssh.cmd_remote(context[:auth], context[:server])
      |> String.to_char_list |> :exec.run([:stdout, :stderr])

    Process.sleep(1000)

    udp_server = Socket.UDP.open!()
    :ok = udp_server |> Socket.Datagram.send!(
      msg <> "\r\n", {"127.0.0.1", origin_port})

    {:ok, {^expected_msg, _client}} = 
      udp_server |> Socket.Datagram.recv([timeout: 1000])
  end
end
