defmodule Fusion.NodeManager do
  @moduledoc """
  GenServer that bootstraps and connects a remote BEAM node via SSH.

  The NodeManager:
  1. Uses SSH tunnels (via Connector) to bridge Erlang distribution
  2. Starts a remote Erlang node via SSH with correct EPMD port and cookie
  3. Connects the remote node to the local cluster
  4. Provides lifecycle management (connect/disconnect)
  """

  use GenServer
  require Logger

  alias Fusion.Target
  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net

  @connect_timeout 15_000
  @connect_retry_interval 500
  @default_elixir_path "/usr/bin/env elixir"

  defstruct target: nil,
            status: :disconnected,
            remote_node_name: nil,
            remote_os_pid: nil,
            remote_port: nil,
            epmd_tunnel_port: nil,
            node_tunnel_port: nil,
            tunnel_ports: []

  @type t :: %__MODULE__{}

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
    GenServer.call(server, :disconnect)
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

  def handle_call(:connect, _from, %{status: :connected} = state) do
    {:reply, {:ok, state.remote_node_name}, state}
  end

  def handle_call(:disconnect, _from, %{status: :connected} = state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:disconnect, _from, %{status: :disconnected} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:remote_node, _from, state) do
    {:reply, state.remote_node_name, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({port, {:data, _data}}, state) when is_port(port) do
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _code}}, state) when is_port(port) do
    if port in state.tunnel_ports do
      Logger.warning("Tunnel process exited unexpectedly")
      {:noreply, %{state | status: :disconnected}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:nodedown, node}, %{remote_node_name: node} = state) do
    Logger.warning("Remote node #{node} went down")
    {:noreply, %{state | status: :disconnected}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{status: :connected} = state) do
    do_disconnect(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Private

  defp do_connect(state) do
    target = state.target
    {auth, remote} = Target.to_auth_and_spot(target)

    local_node = ensure_local_node_alive!()
    epmd_port = Net.get_epmd_port()
    remote_node_port = Net.gen_port()
    epmd_tunnel_port = Net.gen_port()

    remote_node_name = gen_remote_node_name(remote.host)

    Logger.info("Connecting to #{remote.host}:#{remote.port} as #{target.username}")

    with {:ok, tunnel_ports} <-
           setup_tunnels(auth, remote, local_node, epmd_port, remote_node_port, epmd_tunnel_port),
         {:ok, remote_port, remote_os_pid} <-
           start_remote_node(auth, remote, remote_node_name, epmd_tunnel_port, remote_node_port),
         :ok <- wait_for_connection(remote_node_name, @connect_timeout) do
      Logger.info("Connected to remote node #{remote_node_name}")
      Node.monitor(remote_node_name, true)

      {:ok,
       %{
         state
         | status: :connected,
           remote_node_name: remote_node_name,
           remote_os_pid: remote_os_pid,
           remote_port: remote_port,
           epmd_tunnel_port: epmd_tunnel_port,
           node_tunnel_port: nil,
           tunnel_ports: tunnel_ports
       }}
    end
  end

  defp setup_tunnels(auth, remote, local_node, epmd_port, remote_node_port, epmd_tunnel_port) do
    ports = []

    # Reverse tunnel: make local node's distribution port accessible on remote
    {:ok, p1, _} =
      Ssh.cmd_port_tunnel(
        auth,
        remote,
        local_node.port,
        %Fusion.Net.Spot{host: "localhost", port: local_node.port},
        :reverse
      )
      |> Exec.capture_std_mon()

    # Forward tunnel: make remote node's distribution port accessible locally
    {:ok, p2, _} =
      Ssh.cmd_port_tunnel(
        auth,
        remote,
        remote_node_port,
        %Fusion.Net.Spot{host: "localhost", port: remote_node_port},
        :forward
      )
      |> Exec.capture_std_mon()

    # Reverse tunnel: make local EPMD accessible on remote via tunneled port
    {:ok, p3, _} =
      Ssh.cmd_port_tunnel(
        auth,
        remote,
        epmd_tunnel_port,
        %Fusion.Net.Spot{host: "localhost", port: epmd_port},
        :reverse
      )
      |> Exec.capture_std_mon()

    {:ok, [p1, p2, p3 | ports]}
  end

  defp start_remote_node(auth, remote, node_name, epmd_port, node_port) do
    cmd = build_remote_node_cmd(node_name, epmd_port, node_port)
    remote_cmd = Ssh.cmd_remote(cmd, auth, remote)
    {:ok, port, os_pid} = Exec.capture_std_mon(remote_cmd)
    {:ok, port, os_pid}
  end

  defp build_remote_node_cmd(node_name, epmd_port, node_port) do
    cookie = Node.get_cookie()

    [
      "ERL_EPMD_PORT=#{epmd_port}",
      @default_elixir_path,
      "--sname #{node_name}",
      "--cookie #{cookie}",
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
    # Disconnect from the remote node
    if state.remote_node_name do
      Node.disconnect(state.remote_node_name)
    end

    # Kill the remote Elixir process
    if state.remote_os_pid do
      kill_remote_process(state)
    end

    # Close tunnel ports
    for port <- state.tunnel_ports, Port.info(port) != nil do
      Port.close(port)
    end

    %{state | status: :disconnected, remote_node_name: nil, tunnel_ports: []}
  end

  defp kill_remote_process(state) do
    {auth, remote} = Target.to_auth_and_spot(state.target)
    kill_cmd = "kill #{state.remote_os_pid} 2>/dev/null || true"
    Ssh.cmd_remote(kill_cmd, auth, remote) |> Exec.run_sync_capture_std()
  rescue
    _ -> :ok
  end

  defp ensure_local_node_alive! do
    unless Node.alive?() do
      raise "Local node must be alive (started with --sname or --name) to use Fusion"
    end

    Net.get_erl_node()
  end

  defp gen_remote_node_name(_host) do
    # Always use @localhost because all distribution traffic goes through SSH tunnels
    # that bind on localhost. Using the actual remote hostname would bypass the tunnels.
    id = :rand.uniform(999_999) |> Integer.to_string() |> String.pad_leading(6, "0")
    :"fusion_worker_#{id}@localhost"
  end
end
