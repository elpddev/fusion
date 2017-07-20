defmodule Fusion.Utilities.Erl do

	alias Fusion.Net.ErlNode
  alias Fusion.Net.Server

  @moduledoc """
  A wrapper module around erlang erl cli commands.
  """

	@default_erl_path "/usr/bin/env erl"

  @doc """
	Generate command for invoking erl node with inet loader.

  ## Examples

  iex> cmd_erl_inet_loader(
  ...>  %Fusion.Net.ErlNode{name: "worker@localhost", port: 5123, cookie: "abcd1234"}, 
  ...>  %Fusion.Net.Server{port: 6234},
  ...> "127.0.0.1",
  ...> "/erl")
  "ERL_EPMD_PORT=6234 /erl -loader inet -hosts 127.0.0.1 -id worker@localhost -sname worker@localhost -setcookie abcd1234 -noinput -kernel inet_dist_listen_min 5123 -kernel inet_dist_listen_max 5123"
  """

  def cmd_erl_inet_loader(
    node,
    epmd_server,
		boot_server \\ "127.0.0.1",
    erl_path \\ @default_erl_path
  )

  def cmd_erl_inet_loader(
    %ErlNode{} = node,
    %Server{} = epmd_server,
		boot_server, 
    erl_path
  ) do

	 [                            
      "ERL_EPMD_PORT=#{epmd_server.port}",     
      "#{erl_path}",                    
      "-loader inet",
      "-hosts #{boot_server}",               
      "-id #{node.name}",
      "-sname #{node.name}",            
      "-setcookie #{node.cookie}",      
      "-noinput",
      "-kernel inet_dist_listen_min #{node.port}",
      "-kernel inet_dist_listen_max #{node.port}"
    ] 
		|> Enum.join(" ")
  end
end
