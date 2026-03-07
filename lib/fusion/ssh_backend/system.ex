defmodule Fusion.SshBackend.System do
  @moduledoc """
  SSH backend that shells out to the system `ssh` and `sshpass` binaries.

  This is the legacy backend. Use `Fusion.SshBackend.Erlang` (the default)
  for a pure-Erlang implementation with no system binary dependencies.
  """

  @behaviour Fusion.SshBackend

  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot

  defmodule Conn do
    @moduledoc false
    defstruct auth: nil, remote: nil, tunnels: [], os_pids: []
  end

  @impl true
  def connect(%Fusion.Target{} = target) do
    {auth, remote} = Fusion.Target.to_auth_and_spot(target)
    {:ok, %Conn{auth: auth, remote: remote}}
  end

  @impl true
  def forward_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    to_spot = %Spot{host: connect_host, port: connect_port}

    cmd =
      Ssh.cmd_port_tunnel(conn.auth, conn.remote, listen_port, to_spot, :forward)

    case Exec.capture_std_mon(cmd) do
      {:ok, _port, _os_pid} ->
        {:ok, listen_port}

      error ->
        error
    end
  end

  @impl true
  def reverse_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    to_spot = %Spot{host: connect_host, port: connect_port}

    cmd =
      Ssh.cmd_port_tunnel(conn.auth, conn.remote, listen_port, to_spot, :reverse)

    case Exec.capture_std_mon(cmd) do
      {:ok, _port, _os_pid} ->
        {:ok, listen_port}

      error ->
        error
    end
  end

  @impl true
  def exec(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)
    Exec.run_sync_capture_std(cmd)
  end

  @impl true
  def exec_async(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)

    case Exec.capture_std_mon(cmd) do
      {:ok, port, _os_pid} -> {:ok, port}
      error -> error
    end
  end

  @impl true
  def close(%Conn{} = _conn) do
    :ok
  end
end
