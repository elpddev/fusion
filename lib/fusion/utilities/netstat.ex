defmodule Fusion.Utilities.Netstat do
  @moduledoc """
  Wrapper around netstat cli utility.
  """

  @doc """

  ## Examples
  
  iex> cmd_netstat_port_grep(3005) 
  "netstat -tulpn | grep :3005"
  """
  def cmd_netstat_port_grep(port) do
    "netstat -tulpn | grep :#{port}"
  end
end
