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

    true = Regex.match?(netcat_port_greped_regex(target_port), out)
  end

  def assert_local_port_up(target_port) do
    rep = Netstat.cmd_netstat_port_grep(target_port)
    |> Exec.run_sync_capture_std
    {:ok, [stdout: [out], stderr: [_]]} = rep |> IO.inspect

    true = Regex.match?(netcat_port_greped_regex(target_port), out)
  end

  def netcat_port_greped_regex(target_port) do
    ~r/tcp.*127.0.0.1:#{target_port}.*LISTEN/
  end
end
