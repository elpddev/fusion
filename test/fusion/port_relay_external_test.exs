defmodule Fusion.PortRelayExternalTest do
  use ExUnit.Case

  alias Fusion.Test.Helpers.Docker
  alias Fusion.PortRelay
  alias Fusion.Net
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Socat
  alias Fusion.Utilities.Netcat
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Telnet
  alias Fusion.Test.Helpers.Assert

  setup_all _context do
    Application.ensure_started(:dockerex)
    HTTPoison.start # dockerex dependecy
    :ok
  end

  setup context do                      
    if context[:activate_node] do
      {:ok, _} = Node.start(:"master@localhost", :shortnames)
    end

    remote =  case context[:provision_remote] do
      true ->
        %{ container_id: container_id, server: server, auth: auth } = 
          Docker.init_docker_container("fusion_tester")
        Process.sleep(1000)                 
        %{auth: auth, server: server, container_id: container_id}
      _ -> nil
    end

    on_exit fn ->                       
      if context[:activate_node], do: Node.stop()
      if context[:provision_remote] do 
        Process.sleep(500)                
        Docker.remove_docker_container(remote.container_id)
      end
    end 
        
    {:ok, [remote: remote]} 
  end

  test "activate tcp->udp relay successfuly" do
    from_port = Net.gen_port()
    to_port = Net.gen_port()
    msg = "ping from client"
    expected_msg = "#{msg}\r\n"

    {:ok, _} = PortRelay.start_link_now(from_port, :tcp, to_port, :udp)

    Assert.assert_local_port_up(from_port)

    {:ok, _, _} = Socat.cmd_udp_echo_server(to_port)
    |> Exec.run_printall

    Process.sleep(1000)

    {:ok, socket} = Socket.TCP.connect("localhost", from_port)

    socket |> Socket.Stream.send!(msg <> "\r\n")
    ^expected_msg = socket |> Socket.Stream.recv!
  end

  test "activate udp->tcp relay successfuly" do
    from_port = Net.gen_port()
    to_port = Net.gen_port()
    msg = "ping from client"
    expected_msg = "#{msg}\r\n"

    {:ok, _} = PortRelay.start_link_now(from_port, :udp, to_port, :tcp)

    Assert.assert_local_port_up(from_port)

		Netcat.cmd_echo_server(to_port)
    |> Exec.run_printall

    Process.sleep(1000)

    udp_server = Socket.UDP.open!()
    :ok = udp_server |> Socket.Datagram.send!(msg <> "\r\n", {"127.0.0.1", from_port})
    {:ok, {^expected_msg, _client}} = udp_server |> Socket.Datagram.recv
  end

  @tag provision_remote: true
  test "activate remote tcp->udp relay successfuly", %{remote: %{auth: auth, server: server}} do
    from_port = Net.gen_port()
    to_port = Net.gen_port()
    msg = "ping from client"
    expected_msg = "#{msg}\r\n"

    {:ok, _} = PortRelay.start_link_now(auth, server, from_port, :tcp, to_port, :udp)

    Process.sleep(1000)
    Assert.assert_remote_port_up(auth, server, from_port)

    {:ok, _netcat_pid, netcat_oid} = 
      Netcat.cmd_listen_udp(to_port)
      |> Ssh.cmd_remote(auth, server)
      |> String.to_char_list |> :exec.run([:stdout, :stderr])

    Process.sleep(1000)

    #TODO: telnet return code error on one line telnet. how to change it to success code 0.
    Telnet.cmd_telnet_message("localhost", from_port, msg)
    |> Ssh.cmd_remote(auth, server)
    |> Exec.run_sync_printall()

    receive do
      {:stdout, ^netcat_oid, ^expected_msg} -> :ok
    after 
      5000 -> 
        raise "did not got expected message"
    end
  end

  @tag provision_remote: true
  test "activate remote udp->tcp relay successfuly", %{remote: %{auth: auth, server: server}} do
    from_port = Net.gen_port()
    to_port = Net.gen_port()
    msg = "ping from client"
    expected_msg = "#{msg}"

    {:ok, _} = PortRelay.start_link_now(auth, server, from_port, :udp, to_port, :tcp)

    Process.sleep(2000)
    Assert.assert_remote_port_up(auth, server, from_port)

    {:ok, _netcat_pid, netcat_oid} = 
      Netcat.cmd_listen(to_port)
      |> Ssh.cmd_remote(auth, server)
      |> String.to_char_list |> :exec.run([:stdout, :stderr])

    Process.sleep(1000)

    Netcat.cmd_send_udp_message("localhost", from_port, msg)
    |> Ssh.cmd_remote(auth, server)
    |> Exec.run_sync_printall()

    receive do
      {:stdout, ^netcat_oid, ^expected_msg} -> :ok
    after 
      5000 -> 
        raise "did not got expected message"
    end
  end

  #todo: capture failure in genserver
  #test "fail activate tcp->udp relay with not supported combination" do
  #  from_port = Net.gen_port()
  #  to_port = Net.gen_port()

  #  PortRelay.start_now(from_port, :tcp, to_port, :tcp)
  #  PortRelay.start_now(from_port, :udp, to_port, :udp)
  #end
end
