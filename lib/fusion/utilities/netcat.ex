defmodule Fusion.Utilities.Netcat do
  @moduledoc """
  Wrapper module around netcat cli utility.
  """
  
  alias Fusion.Utilities.Bash

  @doc """

  ## Examples

  iex> cmd_listen(3456) 
  "nc -l 3456"
  """
  def cmd_listen(port) do
    "nc -l #{port}"
  end

  def cmd_listen_udp(port) do
    "nc -u -l #{port}"
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

  @doc """

  iex> cmd_send_udp_message("localhost", 3455, "hello")
  "echo -n hello | nc -4u -q1 localhost 3455"
  """
  def cmd_send_udp_message(host, port, msg) do
    "echo -n \"#{Bash.escape_str(msg)}\" | nc -4u -q1 #{host} #{port}"
  end
end
