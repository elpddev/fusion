defmodule Fusion.Net do
  @moduledoc "Network utilities for Erlang distribution."

  alias Fusion.Net.ErlNode

  @default_epmd_port 4369

  @doc """
  Generate a random available port in the ephemeral range.

  Briefly binds to port 0 to get an OS-assigned free port. Falls back
  to random selection if binding fails.
  """
  @spec gen_port() :: pos_integer()
  def gen_port do
    case :gen_tcp.listen(0, []) do
      {:ok, socket} ->
        try do
          {:ok, port} = :inet.port(socket)
          port
        after
          :gen_tcp.close(socket)
        end

      {:error, _} ->
        Enum.random(49152..65535)
    end
  end

  @doc "Get the current node's ErlNode info."
  @spec get_erl_node({String.t(), String.t()}, atom()) ::
          {:ok, ErlNode.t()} | {:error, term()}
  def get_erl_node(name_host \\ node_self(), cookie \\ Node.get_cookie()) do
    {name, host} = name_host

    with {:ok, port} <- get_self_port_from_epmd(name_host) do
      {:ok, %ErlNode{name: name, host: host, port: port, cookie: cookie}}
    end
  end

  @doc "Query EPMD for the current node's distribution port."
  @spec get_self_port_from_epmd({String.t(), String.t()}) ::
          {:ok, pos_integer()} | {:error, term()}
  def get_self_port_from_epmd(name_host \\ node_self()) do
    {name, host} = name_host

    case :erl_epmd.port_please(String.to_charlist(name), String.to_charlist(host)) do
      {:port, port, _} -> {:ok, port}
      :noport -> {:error, {:epmd_lookup_failed, "node #{name}@#{host} not registered"}}
      {:error, reason} -> {:error, {:epmd_lookup_failed, reason}}
    end
  end

  @doc """
  Split a node name into {name, host}.

  ## Examples

      iex> Fusion.Net.node_self(:"master@my-computer-v3475-ad345")
      {"master", "my-computer-v3475-ad345"}
  """
  @spec node_self(atom()) :: {String.t(), String.t()}
  def node_self(full_name \\ Node.self()) do
    case full_name |> Atom.to_string() |> String.split("@") do
      [name, host] ->
        {name, host}

      _ ->
        raise ArgumentError, "expected a full node name (name@host), got: #{inspect(full_name)}"
    end
  end

  @doc """
  Generate `count` unique ports. Prevents self-collision when multiple
  ports are needed simultaneously (e.g., for tunnels).
  """
  @spec gen_unique_ports(pos_integer()) :: [pos_integer()]
  def gen_unique_ports(count) do
    do_gen_unique_ports(count, MapSet.new(), [])
  end

  defp do_gen_unique_ports(0, _seen, acc), do: Enum.reverse(acc)

  defp do_gen_unique_ports(remaining, seen, acc) do
    port = gen_port()

    if MapSet.member?(seen, port) do
      do_gen_unique_ports(remaining, seen, acc)
    else
      do_gen_unique_ports(remaining - 1, MapSet.put(seen, port), [port | acc])
    end
  end

  @doc "Get the EPMD port (from ERL_EPMD_PORT env var or default 4369)."
  @spec get_epmd_port(String.t() | nil, pos_integer()) :: pos_integer()
  def get_epmd_port(
        port_str \\ System.get_env("ERL_EPMD_PORT"),
        default \\ @default_epmd_port
      ) do
    case port_str do
      nil ->
        default

      _ ->
        case Integer.parse(port_str) do
          {port, ""} when port > 0 and port <= 65535 -> port
          _ -> raise ArgumentError, "invalid ERL_EPMD_PORT: #{inspect(port_str)}"
        end
    end
  end
end
