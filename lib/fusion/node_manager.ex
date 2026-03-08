defmodule Fusion.NodeManager do
  @moduledoc """
  GenServer that bootstraps and connects a remote BEAM node via SSH.

  The NodeManager:
  1. Uses a pluggable SSH backend (via `target.ssh_backend`) for connections and tunnels
  2. Starts a remote Erlang node via SSH with correct EPMD port and cookie
  3. Connects the remote node to the local cluster
  4. Provides lifecycle management (connect/disconnect)
  """

  use GenServer
  require Logger

  alias Fusion.Target
  alias Fusion.Net

  @connect_timeout 15_000
  @connect_retry_interval 500
  @tunnel_retry_attempts 5
  @tunnel_retry_interval 200
  @default_elixir_path "/usr/bin/env elixir"
  @tunnel_connect_host "127.0.0.1"

  defstruct target: nil,
            status: :disconnected,
            remote_node_name: nil,
            conn: nil

  @type t :: %__MODULE__{
          target: Target.t() | nil,
          status: :disconnected | :connected,
          remote_node_name: atom() | nil,
          conn: term() | nil
        }

  ## Public API

  @doc "Start the NodeManager GenServer."
  def start_link(%Target{} = target, opts \\ []) do
    GenServer.start_link(__MODULE__, target, opts)
  end

  @doc """
  Connect to the remote target. Sets up tunnels, bootstraps a BEAM node,
  and connects it to the local cluster.
  Returns `{:ok, remote_node_name}` or `{:error, reason}`.
  """
  def connect(server, timeout \\ @connect_timeout) do
    GenServer.call(server, :connect, timeout + 5_000)
  end

  @doc "Disconnect from the remote node and clean up."
  def disconnect(server) do
    GenServer.call(server, :disconnect, 60_000)
  end

  @doc "Get the remote node name (atom) if connected."
  def remote_node(server) do
    GenServer.call(server, :remote_node)
  end

  @doc "Get the current status (:disconnected | :connected)."
  def status(server) do
    GenServer.call(server, :status)
  end

  ## Callbacks

  @impl true
  def init(%Target{} = target) do
    backend = target.ssh_backend

    unless Code.ensure_loaded?(backend) and
             Enum.all?(Fusion.SshBackend.behaviour_info(:callbacks), fn {fun, arity} ->
               function_exported?(backend, fun, arity)
             end) do
      raise ArgumentError,
            "#{inspect(backend)} does not implement the Fusion.SshBackend behaviour"
    end

    {:ok, %__MODULE__{target: target}}
  end

  @impl true
  def handle_call(:connect, _from, %{status: :disconnected} = state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:reply, {:ok, new_state.remote_node_name}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:connect, _from, %{status: :connected} = state) do
    {:reply, {:ok, state.remote_node_name}, state}
  end

  @impl true
  def handle_call(:disconnect, _from, %{status: :connected} = state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:disconnect, _from, %{status: :disconnected} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:remote_node, _from, state) do
    {:reply, state.remote_node_name, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:nodedown, node}, %{remote_node_name: node, status: :connected} = state) do
    Logger.warning("Remote node #{node} went down")
    new_state = do_disconnect(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{status: :connected} = state) do
    do_disconnect(state)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  ## Private

  defp do_connect(state) do
    target = state.target
    backend = target.ssh_backend

    with {:ok, local_node} <- ensure_local_node_alive() do
      [remote_node_port, epmd_tunnel_port] = Net.gen_unique_ports(2)

      ports = %{
        epmd: Net.get_epmd_port(),
        remote_node: remote_node_port,
        epmd_tunnel: epmd_tunnel_port
      }

      remote_node_name = gen_remote_node_name(target.host)

      Logger.info("Connecting to #{target.host}:#{target.port} as #{target.username}")

      with {:ok, conn} <- backend.connect(target) do
        case do_connect_with_conn(state, backend, conn, local_node, remote_node_name, ports) do
          {:ok, _} = success ->
            success

          {:error, _} = error ->
            cleanup_failed_connect(backend, conn, remote_node_name)
            error
        end
      end
    end
  end

  defp do_connect_with_conn(state, backend, conn, local_node, remote_node_name, ports) do
    with :ok <- setup_tunnels(backend, conn, local_node, ports),
         :ok <- launch_remote_node(backend, conn, remote_node_name, ports),
         :ok <- wait_for_connection(remote_node_name, @connect_timeout) do
      Logger.info("Connected to remote node #{remote_node_name}")
      Node.monitor(remote_node_name, true)

      {:ok, %{state | status: :connected, remote_node_name: remote_node_name, conn: conn}}
    end
  end

  defp setup_tunnels(backend, conn, local_node, ports) do
    with {:ok, _} <-
           retry_tunnel(fn ->
             backend.reverse_tunnel(conn, local_node.port, @tunnel_connect_host, local_node.port)
           end),
         {:ok, _} <-
           backend.forward_tunnel(
             conn,
             ports.remote_node,
             @tunnel_connect_host,
             ports.remote_node
           ),
         {:ok, _} <-
           retry_tunnel(fn ->
             backend.reverse_tunnel(conn, ports.epmd_tunnel, @tunnel_connect_host, ports.epmd)
           end) do
      :ok
    end
  end

  # Retry tunnel setup to handle transient :not_accepted errors that occur when
  # a previous SSH connection's tunnel listener hasn't been fully released yet.
  defp retry_tunnel(fun, attempt \\ 1) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, :not_accepted} when attempt < @tunnel_retry_attempts ->
        Logger.debug("Tunnel not accepted, retrying (#{attempt}/#{@tunnel_retry_attempts})")
        Process.sleep(@tunnel_retry_interval)
        retry_tunnel(fun, attempt + 1)

      error ->
        error
    end
  end

  defp launch_remote_node(backend, conn, remote_node_name, ports) do
    cmd = build_remote_node_cmd(remote_node_name, ports.epmd_tunnel, ports.remote_node)

    case backend.exec_async(conn, cmd) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp cleanup_failed_connect(backend, conn, remote_node_name) do
    kill_remote_process(backend, conn, remote_node_name)
    safe_call(fn -> backend.close(conn) end)
  end

  # Kill the remote BEAM process via SSH exec. Used as cleanup when the
  # distribution layer is unavailable. remote_node_name is internally generated
  # (not user input), so shell interpolation here is safe.
  defp kill_remote_process(backend, conn, remote_node_name) do
    safe_call(fn ->
      backend.exec(
        conn,
        "kill -9 $(pgrep -f -- '--sname #{remote_node_name}') 2>/dev/null || true"
      )
    end)
  end

  defp safe_call(fun) do
    try do
      fun.()
    rescue
      e ->
        Logger.debug("Cleanup call failed: #{inspect(e)}")
        :ok
    catch
      _, reason ->
        Logger.debug("Cleanup call failed: #{inspect(reason)}")
        :ok
    end
  end

  # Extension point: if you need alternate remote node types (e.g., rebar3-based
  # Erlang nodes), this is the function to replace.
  #
  # All values interpolated into this command (cookie, node_name, ports) come
  # from trusted internal sources — cookie from Node.get_cookie(), node_name
  # from gen_remote_node_name/1, and ports from Net.gen_port/0.
  #
  # Note: the cookie is visible via `ps aux` on the remote host. For multi-tenant
  # environments, consider using ~/.erlang.cookie instead.
  defp build_remote_node_cmd(node_name, epmd_port, node_port) do
    cookie = Node.get_cookie()

    [
      "ERL_EPMD_PORT=#{epmd_port}",
      @default_elixir_path,
      "--sname #{node_name}",
      "--cookie '#{cookie}'",
      "--erl \"-kernel inet_dist_listen_min #{node_port} inet_dist_listen_max #{node_port}\"",
      "-e \"Process.sleep(:infinity)\""
    ]
    |> Enum.join(" ")
  end

  defp wait_for_connection(node_name, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_connection(node_name, deadline)
  end

  defp do_wait_for_connection(node_name, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :connect_timeout}
    else
      case Node.connect(node_name) do
        true ->
          :ok

        false ->
          Process.sleep(@connect_retry_interval)
          do_wait_for_connection(node_name, deadline)

        :ignored ->
          {:error, :local_node_not_alive}
      end
    end
  end

  defp do_disconnect(state) do
    backend = state.target.ssh_backend

    if state.remote_node_name do
      # Stop monitoring before teardown to prevent :nodedown re-entering do_disconnect
      safe_call(fn -> Node.monitor(state.remote_node_name, false) end)

      # Request graceful shutdown via async RPC (cast won't block if remote is hung)
      safe_call(fn -> :rpc.cast(state.remote_node_name, System, :stop, [0]) end)
      safe_call(fn -> Node.disconnect(state.remote_node_name) end)

      # Belt-and-suspenders: always kill via SSH as well, since rpc.cast is
      # fire-and-forget and we cannot know if the graceful shutdown succeeded.
      if state.conn do
        kill_remote_process(backend, state.conn, state.remote_node_name)
      end
    end

    # Close SSH connection
    if state.conn do
      safe_call(fn -> backend.close(state.conn) end)
    end

    %{state | status: :disconnected, remote_node_name: nil, conn: nil}
  end

  defp ensure_local_node_alive do
    if Node.alive?() do
      Net.get_erl_node()
    else
      {:error, :local_node_not_alive}
    end
  end

  # Always use @localhost because all distribution traffic goes through SSH tunnels
  # that bind on localhost. Using the actual remote hostname would bypass the tunnels.
  # The host label is included for debuggability when multiple connections exist.
  defp gen_remote_node_name(host) do
    id = :rand.bytes(8) |> Base.encode16(case: :lower)
    label = host |> String.replace(~r/[^a-zA-Z0-9]/, "_") |> String.slice(0, 20)
    :"fusion_#{label}_#{id}@localhost"
  end
end
