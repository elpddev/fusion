defmodule Fusion.SshPortTunnelExternalTest do
  use ExUnit.Case

  alias Fusion.Test.Helpers.Docker
  alias Fusion.SshPortTunnel
  alias Fusion.Net.Spot
  alias Fusion.Utilities.Telnet
  alias Fusion.Utilities.Netcat
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Bash
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

  @tag :external
  test "start forward tunnel successfuly", context do
    origin_port = Net.gen_port()
    remote_port = Net.gen_port()
    msg = "ping from client"
    expected_msg = "#{msg}\r\n"

    {:ok, _} = SshPortTunnel.start_link_now(
      context[:auth], context[:server], 
      :forward, 
			origin_port,
      %Spot{host: "localhost", port: remote_port} 
    )

    {:ok, _, _} = Ssh.cmd("", context[:auth], context[:server]) <> " " <>  
		"\"#{Netcat.cmd_echo_server(remote_port) |> Bash.escape_str()}\""
    |> Exec.run_printall

    Process.sleep(1000)

    {:ok, socket} = Socket.TCP.connect("localhost", origin_port)

    socket |> Socket.Stream.send!(msg <> "\r\n")
    ^expected_msg = socket |> Socket.Stream.recv!
  end

  @tag :external
  test "start reverse tunnel successfuly", context do
		origin_port = Net.gen_port()
    remote_port = Net.gen_port()
    message = "ping from client"        
    expected_message = message <> "\r\n"
    
    server = Socket.TCP.listen! origin_port

    {:ok, _} = SshPortTunnel.start_link_now(
      context[:auth], context[:server], 
      :reverse, 
			remote_port,
      %Spot{host: "localhost", port: origin_port} 
    )

		Process.sleep(1000)

    Ssh.cmd("", context[:auth], context[:server]) <> " " <>  
		Telnet.cmd_telnet_message("localhost", remote_port, message)
    |> Exec.run_sync_printall

    {:ok, client} = Socket.TCP.accept(server, timeout: 1000)
    case client |> Socket.Stream.recv! do      
      ^expected_message -> :ok
    end
	 
  end

  @tag :external
  test "start a remote ssh tunnel and get expected fail on nonexisted remote", context do
		non_existing_server = %Spot{host: "10.0.0.200", port: 55223}

    {:ok, pid} = SshPortTunnel.start_now(
      context[:auth], non_existing_server, 
      :reverse, 
			Net.gen_port(),
      %Spot{host: "localhost", port: Net.gen_port()} 
    )

    mon_ref = Process.monitor(pid)

    receive do
      {:DOWN, ^mon_ref, :process, _, :conn_refused} -> :ok
    after
      5000 ->
        raise "did not received down for connection refused"
    end
  end

end
