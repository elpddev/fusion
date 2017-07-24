defmodule Fusion.Utilities.Telnet do
  @moduledoc """
  """

	@doc """
	
  ## Examples

  iex> cmd_telnet_message("localhost", 3456, "hello") 
  "telnet -e E localhost 3456 <<< 'hello'"
	"""
  def cmd_telnet_message(host, port, message) do
    #"telnet localhost #{origin_port} << EOF\n#{message}\nEOF"
    "telnet -e E #{host} #{port} <<< '#{message}'"
  end

end
