defmodule Fusion.Utilities.NetstatExternalTest do
  use ExUnit.Case

  alias Fusion.Utilities.Netstat
  alias Fusion.Utilities.Netcat

  test "cmd_netstat_port_grep", _context do
    port = Fusion.Net.gen_port()
    {:ok, _, _} = Netcat.cmd_listen(port)
    |> String.to_char_list |> :exec.run([])

    {:ok, [stdout: [out]]} = Netstat.cmd_netstat_port_grep(port)   
    |> String.to_char_list |> :exec.run([:sync, :stdout])
    
    assert Regex.match?(~r/#{port}/, out)
  end
end
