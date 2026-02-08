defmodule Fusion.Net do
  @moduledoc "Network utilities for Erlang distribution."

  alias Fusion.Net.ErlNode

  @default_epmd_port 4369

  @doc "Generate a random port in the ephemeral range."
  def gen_port(start_range \\ 49152, end_range \\ 65535) do
    range = end_range - start_range
    start_range + :rand.uniform(range)
  end

  @doc "Get the current node's ErlNode info."
  def get_erl_node(
        {name, host} \\ node_self(),
        port \\ get_self_port_from_epmd(),
        cookie \\ Node.get_cookie()
      ) do
    %ErlNode{name: name, host: host, port: port, cookie: cookie}
  end

  @doc "Query EPMD for the current node's distribution port."
  def get_self_port_from_epmd({name, host} \\ node_self()) do
    {:port, port, _} =
      :erl_epmd.port_please(
        String.to_charlist(name),
        String.to_charlist(host)
      )

    port
  end

  @doc """
  Split a node name into {name, host}.

  ## Examples

      iex> Fusion.Net.node_self(:"master@my-computer-v3475-ad345")
      {"master", "my-computer-v3475-ad345"}
  """
  def node_self(full_name \\ Node.self()) do
    full_name |> Atom.to_string() |> String.split("@") |> List.to_tuple()
  end

  @doc "Get the EPMD port (from ERL_EPMD_PORT env var or default 4369)."
  def get_epmd_port(
        port_str \\ System.get_env("ERL_EPMD_PORT"),
        default \\ @default_epmd_port
      ) do
    case port_str do
      nil -> default
      _ -> String.to_integer(port_str)
    end
  end
end
