defmodule Fusion.Net do
  #alias Fusion.Net.Spot
  alias Fusion.Net.ErlNode

  @default_epmd_port 4369

  @doc """
  """
  def gen_port(start_range \\ 49152, end_range \\ 65535) do
    range = end_range - start_range
    start_range + :rand.uniform(range)
  end

  @doc """
  Get erlang network node details. Return name/host, port, and cookie.

  ## Examples

  iex> get_erl_node({"master", "localhost"}, 5678, :abcd1234)
  %Fusion.Net.ErlNode{name: "master", host: "localhost", port: 5678, cookie: :abcd1234}
  """
  def get_erl_node(
    {name, host} \\ node_self(),
    port \\ get_self_port_from_epmd(),
    cookie \\ Node.get_cookie()
  ) do

    %ErlNode{name: name, host: host, port: port, cookie: cookie}
  end

  @doc """
  Get erlang network node self port. Internally use epmd for query self info. 
  """
  def get_self_port_from_epmd({name, host} \\ node_self()) do
    {:port, port, _} = :erl_epmd.port_please(
		  name |> String.to_charlist(),
			host |> String.to_charlist()	
		)
    
    port
  end

  @doc """
  Get erlang network node self name parsed to tupple. {name, host}.

  ## Examples
  
  iex> Fusion.Net.node_self(:"master@my-computer-v3475-ad345")
  {"master", "my-computer-v3475-ad345"}
  """
  def node_self(full_name \\ Node.self()) do
    full_name |> Atom.to_string |> String.split("@") |> List.to_tuple
  end

  @doc """
  Get epmd service external port.
  """
  def get_epmd_port(
    port_str \\ System.get_env("ERL_EPMD_PORT"),
    default \\ @default_epmd_port
  ) do

   # todo: Build logic based on: epmd_listen_sup.get_port_no/0
   # https://github.com/erlang/epmd/blob/master/src/epmd_listen_sup.erl

    case port_str do
      nil -> default
      _ -> String.to_integer(port_str)
    end
  end

end
