defmodule Fusion.SshBackend.System do
  @moduledoc """
  SSH backend that shells out to the system `ssh` and `sshpass` binaries.

  This is the legacy backend. Use `Fusion.SshBackend.Erlang` (the default)
  for a pure-Erlang implementation with no system binary dependencies.
  """

  @behaviour Fusion.SshBackend

  require Logger

  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot

  @drain_timeout 300_000

  defmodule Conn do
    @moduledoc false
    @enforce_keys [:auth, :remote, :resource_tracker]
    defstruct [:auth, :remote, :resource_tracker]

    defimpl Inspect do
      def inspect(%{auth: auth, remote: remote}, opts) do
        redacted_auth =
          case auth do
            %{password: _} = a -> %{a | password: "**REDACTED**"}
            other -> other
          end

        Inspect.Algebra.concat([
          "#Fusion.SshBackend.System.Conn<",
          Inspect.Algebra.to_doc(%{auth: redacted_auth, remote: remote}, opts),
          ">"
        ])
      end
    end
  end

  # Note: unlike the Erlang backend, connect/1 does not establish a TCP connection.
  # Connection validation is deferred until the first tunnel or exec call.
  @impl true
  def connect(%Fusion.Target{} = target) do
    {auth, remote} = to_auth_and_spot(target)
    {:ok, tracker} = Agent.start_link(fn -> [] end)
    {:ok, %Conn{auth: auth, remote: remote, resource_tracker: tracker}}
  end

  defp to_auth_and_spot(%Fusion.Target{} = target) do
    auth =
      case target.auth do
        {:key, path} -> %{username: target.username, key_path: path}
        {:password, pass} -> %{username: target.username, password: pass}
      end

    remote = %Spot{host: target.host, port: target.port}
    {auth, remote}
  end

  @impl true
  def forward_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    do_tunnel(conn, listen_port, connect_host, connect_port, :forward)
  end

  @impl true
  def reverse_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    do_tunnel(conn, listen_port, connect_host, connect_port, :reverse)
  end

  defp do_tunnel(conn, listen_port, connect_host, connect_port, direction) do
    to_spot = %Spot{host: connect_host, port: connect_port}
    cmd = Ssh.cmd_port_tunnel(conn.auth, conn.remote, listen_port, to_spot, direction)

    case Exec.capture_std_mon(cmd, env: password_env(conn.auth)) do
      {:ok, port, os_pid} ->
        Agent.update(conn.resource_tracker, &[{port, os_pid} | &1])
        {:ok, listen_port}

      error ->
        error
    end
  end

  @impl true
  def exec(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)

    case Exec.run_sync_capture_std(cmd, env: password_env(conn.auth)) do
      {:ok, output} -> {:ok, output}
      {:error, {code, output}} -> {:error, {:exit_status, code, output, ""}}
    end
  end

  @impl true
  def exec_async(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)

    port_env =
      Enum.map(password_env(conn.auth), fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)

    pid =
      spawn(fn ->
        port =
          Port.open({:spawn_executable, "/bin/sh"}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:args, ["-c", cmd]},
            {:env, port_env}
          ])

        drain_port(port)
      end)

    {:ok, pid}
  end

  defp drain_port(port) do
    receive do
      {^port, {:data, _data}} -> drain_port(port)
      {^port, {:exit_status, _code}} -> :ok
    after
      @drain_timeout ->
        Port.close(port)
        Logger.warning("System exec_async drain_port timed out after #{@drain_timeout}ms")
    end
  end

  defp password_env(%{password: password}), do: [{"SSHPASS", password}]
  defp password_env(_auth), do: []

  @impl true
  def close(%Conn{resource_tracker: tracker} = _conn) do
    resources = Agent.get(tracker, & &1)

    for {port, os_pid} <- resources do
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end

      System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)
    end

    Agent.stop(tracker)
    :ok
  end
end
