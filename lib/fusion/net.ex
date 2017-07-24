defmodule Fusion.Net do
  #alias Fusion.Net.Spot
  alias Fusion.Net.ErlNode

  @doc """
  """
  def gen_port(start_range \\ 49152, end_range \\ 65635) do
    range = end_range - start_range
    start_range + :rand.uniform(range)
  end

  def get_erl_node(
    {name, host} \\ node_self(),
    port \\ get_self_port_from_epmd(),
    cookie \\ Node.get_cookie()
  ) do

    %ErlNode{name: name, host: host, port: port, cookie: cookie}
  end

  def get_self_port_from_epmd({name, host} \\ node_self()) do
    {:port, port, _} = :erl_epmd.port_please(
		  name |> String.to_charlist(),
			host |> String.to_charlist()	
		)
    
    port
  end

  @doc """

  ## Examples
  
  iex> Fusion.Net.node_self(:"master@my-computer-v3475-ad345")
  {"master", "my-computer-v3475-ad345"}
  """
  def node_self(full_name \\ Node.self()) do
    full_name |> Atom.to_string |> String.split("@") |> List.to_tuple
  end
end
