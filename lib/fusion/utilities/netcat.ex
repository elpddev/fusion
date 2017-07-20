defmodule Fusion.Utilities.Netcat do
  @moduledoc """
  Wrapper module around netcat cli utility.
  """

  @doc """

  ## Examples

  iex> cmd_listen(3456) 
  "nc -l 3456"
  """
  def cmd_listen(port) do
    "nc -l #{port}"
  end


  @doc """
  Generate command for a netcat echo server. 

  ## Examples
  
  iex> cmd_echo_server(1234) 
  "rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | while read res; do echo \\\"\$res\\\";done | nc -l 1234 > /tmp/f" 
  """
  def cmd_echo_server(port) do
    "rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | while read res; do echo \"$res\";done | nc -l #{port} > /tmp/f"
  end

end
