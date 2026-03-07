defmodule Fusion.SshBackend.Erlang do
  @moduledoc """
  SSH backend using Erlang's built-in :ssh module.

  This is the default backend. It uses OTP's SSH implementation
  for connections, tunnels, and remote command execution.
  """

  require Logger

  @behaviour Fusion.SshBackend

  @connect_timeout 15_000
  @exec_timeout 30_000

  @impl true
  def connect(%Fusion.Target{} = target) do
    :ssh.start()

    Logger.debug("SSH connecting to #{target.host}:#{target.port} as #{target.username}")

    host = String.to_charlist(target.host)
    opts = connect_opts(target)

    case :ssh.connect(host, target.port, opts, @connect_timeout) do
      {:ok, conn} ->
        Logger.debug("SSH connected to #{target.host}:#{target.port}")
        {:ok, conn}

      {:error, reason} ->
        Logger.warning(
          "SSH connection to #{target.host}:#{target.port} failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @impl true
  def forward_tunnel(conn, listen_port, connect_host, connect_port) do
    Logger.debug(
      "Creating forward tunnel: localhost:#{listen_port} -> #{connect_host}:#{connect_port}"
    )

    :ssh.tcpip_tunnel_to_server(
      conn,
      ~c"127.0.0.1",
      listen_port,
      String.to_charlist(connect_host),
      connect_port,
      @connect_timeout
    )
  end

  @impl true
  def reverse_tunnel(conn, listen_port, connect_host, connect_port) do
    Logger.debug(
      "Creating reverse tunnel: remote:#{listen_port} -> #{connect_host}:#{connect_port}"
    )

    :ssh.tcpip_tunnel_from_server(
      conn,
      ~c"127.0.0.1",
      listen_port,
      String.to_charlist(connect_host),
      connect_port,
      @connect_timeout
    )
  end

  @impl true
  def exec(conn, command) do
    with {:ok, ch} <- :ssh_connection.session_channel(conn, @exec_timeout),
         :success <- :ssh_connection.exec(conn, ch, String.to_charlist(command), @exec_timeout) do
      collect_output(conn, ch, <<>>, <<>>, nil)
    else
      :failure ->
        Logger.warning("SSH exec failed: :exec_failed")
        {:error, :exec_failed}

      {:error, reason} ->
        Logger.warning("SSH exec failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def exec_async(conn, command) do
    pid =
      spawn(fn ->
        case :ssh_connection.session_channel(conn, @exec_timeout) do
          {:ok, ch} ->
            case :ssh_connection.exec(conn, ch, String.to_charlist(command), @exec_timeout) do
              :success ->
                ref = Process.monitor(conn)

                receive do
                  {:ssh_cm, ^conn, {:closed, ^ch}} -> :ok
                  {:DOWN, ^ref, :process, ^conn, _reason} -> :ok
                end

              :failure ->
                Logger.warning("SSH exec_async failed: exec returned :failure")
            end

          {:error, reason} ->
            Logger.warning("SSH exec_async failed to open channel: #{inspect(reason)}")
        end
      end)

    {:ok, pid}
  end

  @impl true
  def close(conn) do
    :ssh.close(conn)
    Logger.debug("SSH connection closed")
    :ok
  end

  @doc false
  def connect_opts(%Fusion.Target{} = target) do
    base_opts = [
      user: String.to_charlist(target.username),
      silently_accept_hosts: true,
      user_interaction: false
    ]

    auth_opts =
      case target.auth do
        {:password, password} ->
          [password: String.to_charlist(password)]

        {:key, key_path} ->
          [key_cb: {Fusion.SshKeyProvider, key_path: key_path}]
      end

    base_opts ++ auth_opts
  end

  defp collect_output(conn, ch, stdout, stderr, exit_code) do
    receive do
      {:ssh_cm, ^conn, {:data, ^ch, 0, data}} ->
        collect_output(conn, ch, stdout <> data, stderr, exit_code)

      {:ssh_cm, ^conn, {:data, ^ch, 1, data}} ->
        collect_output(conn, ch, stdout, stderr <> data, exit_code)

      {:ssh_cm, ^conn, {:eof, ^ch}} ->
        collect_output(conn, ch, stdout, stderr, exit_code)

      {:ssh_cm, ^conn, {:exit_status, ^ch, code}} ->
        collect_output(conn, ch, stdout, stderr, code)

      {:ssh_cm, ^conn, {:closed, ^ch}} ->
        case exit_code do
          0 -> {:ok, stdout}
          nil -> {:ok, stdout}
          code -> {:error, {:exit_code, code, stdout, stderr}}
        end
    after
      @exec_timeout ->
        :ssh_connection.close(conn, ch)
        {:error, :timeout}
    end
  end
end
