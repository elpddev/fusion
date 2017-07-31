defmodule Fusion.ErlBootServerAnalyzerExternalTest do
  use ExUnit.Case

  alias Fusion.ErlBootServerAnalyzer, as: Analyzer

  @eboot_port 4368 
  @eboot_request 'EBOOTQ'
  @erl_version :erlang.system_info(:version)
  @contact_req_token (@eboot_request ++ @erl_version)

  test "activate and recieve contact request successfuly" do
    {:ok, analyzer} = Analyzer.start_link_now()
    Analyzer.register_for_incoming_req(analyzer)

    remote_node_mock = Socket.UDP.open!()
    {:ok, source_port} = :inet.port(remote_node_mock)
    IO.puts "*** source port"
    IO.inspect(source_port)
    :ok = remote_node_mock |> Socket.Datagram.send!(@contact_req_token, {"127.0.0.1", @eboot_port})

    receive do
      {:incoming_udp_contact_req, {127, 0, 0, 1}, ^source_port} ->
        IO.puts "*** got incoming udp contact req"
      msg -> 
        IO.inspect(msg)
        raise "got unintened message"
    after 
      1000 -> raise "did not got udp discovery message"
    end
  end
end
