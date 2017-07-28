defmodule Fusion.Test.Helpers.Assert do
	alias Fusion.Utilities.Netstat
	alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec

  def assert_remote_port_up(auth, server, target_port) do
    rep = 
      (Ssh.cmd("", auth, server) <> " " <> 
      Netstat.cmd_netstat_port_grep(target_port))
      |> Exec.run_sync_capture_std
    {:ok, [stdout: [out], stderr: [_]]} = rep |> IO.inspect

    true = Regex.match?(netstat_port_greped_regex(target_port), out)
  end

  def assert_local_port_up(target_port) do
    rep = Netstat.cmd_netstat_port_grep(target_port)
    |> Exec.run_sync_capture_std
    {:ok, [stdout: [out], stderr: [_]]} = rep |> IO.inspect

    true = Regex.match?(netstat_port_greped_regex(target_port), out)
  end

  def netstat_port_greped_regex(target_port) do
    ~r/((tcp)|(udp)).*127.0.0.1:#{target_port}.*/
  end
end
