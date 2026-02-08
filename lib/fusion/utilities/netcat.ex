defmodule Fusion.Utilities.Netcat do
  @moduledoc "Wrapper around netcat CLI utility."

  alias Fusion.Utilities.Bash

  @doc """
  Generate netcat listen command.

  ## Examples

      iex> Fusion.Utilities.Netcat.cmd_listen(3456)
      "nc -l 3456"
  """
  def cmd_listen(port), do: "nc -l #{port}"

  @doc "Generate netcat UDP listen command."
  def cmd_listen_udp(port), do: "nc -u -l #{port}"

  @doc ~S"""
  Generate command for a netcat echo server.

  ## Examples

      iex> Fusion.Utilities.Netcat.cmd_echo_server(1234)
      "rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | while read res; do echo \"$res\";done | nc -l 1234 > /tmp/f"
  """
  def cmd_echo_server(port) do
    "rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | while read res; do echo \"$res\";done | nc -l #{port} > /tmp/f"
  end

  @doc ~S"""
  Generate command to send a UDP message.

  ## Examples

      iex> Fusion.Utilities.Netcat.cmd_send_udp_message("localhost", 3455, "hello")
      "echo -n \"hello\" | nc -4u -q1 localhost 3455"
  """
  def cmd_send_udp_message(host, port, msg) do
    "echo -n \"#{Bash.escape_str(msg)}\" | nc -4u -q1 #{host} #{port}"
  end
end
