defmodule Fusion.PortRelayExternalTest do
  use ExUnit.Case

  alias Fusion.PortRelay
  alias Fusion.Net
  alias Fusion.Utilities.Exec
  alias Fusion.Utilities.Socat
  alias Fusion.Utilities.Netcat
  alias Fusion.Test.Helpers.Assert

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
    from_port = 4000 #Net.gen_port()
    to_port = 5000 # Net.gen_port()
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

  #todo: capture failure in genserver
  #test "fail activate tcp->udp relay with not supported combination" do
  #  from_port = Net.gen_port()
  #  to_port = Net.gen_port()

  #  PortRelay.start_now(from_port, :tcp, to_port, :tcp)
  #  PortRelay.start_now(from_port, :udp, to_port, :udp)
  #end
end
