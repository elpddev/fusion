defmodule Fusion.Utilities.Telnet do
  @moduledoc "Wrapper around telnet CLI utility."

  @doc """
  Generate telnet command to send a message.

  ## Examples

      iex> Fusion.Utilities.Telnet.cmd_telnet_message("localhost", 3456, "hello")
      "telnet -e E localhost 3456 <<< 'hello'"
  """
  def cmd_telnet_message(host, port, message) do
    "telnet -e E #{host} #{port} <<< '#{message}'"
  end
end
