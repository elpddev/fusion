defmodule Fusion.Utilities.Netstat do
  @moduledoc """
  Wrapper around netstat cli utility.
  """

  @doc """

  ## Examples
  
  iex> cmd_netstat_port_grep(3005) 
  "netstat -tlpn | grep :3005 | grep LISTEN"
  """
  def cmd_netstat_port_grep(port) do
    "netstat -tlpn | grep :#{port} | grep LISTEN"
  end
end
